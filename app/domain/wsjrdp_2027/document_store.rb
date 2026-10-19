# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "digest"
require "securerandom"

module Wsjrdp2027
  # Stores the files of wsjrdp_documents under the upload root
  # (doc/wsjrdp/documents.md).
  #
  # The upload root is Settings.documents.storage_root, by default
  # <wagon>/private/uploads, where the registration uploads lie; a document
  # keeps its path relative to it (relative_storage_file_path) and the full
  # path it was written to (absolute_storage_file_path). Its folder comes from
  # its subject's kind (Wsjrdp2027::DocumentSubjects), its name from
  # Wsjrdp2027::DocumentFilename.
  #
  # A file is never overwritten: it is written to a temporary file in its
  # folder first (#prepare), then moved to its name (#claim_name) -- the name
  # is taken first by creating an empty file of that name exclusively, which
  # fails when a file has it, and the temporary file then renamed onto it --,
  # and at last its row saved (#place). A name a file or a row has gets the
  # next suffix _1, _2, ... Works on any file system: no hard links, no
  # copying.
  #
  # Every write of a slot goes through Wsjrdp2027::DocumentWrite: it claims
  # the names before it takes the slot's lock, so that only database work
  # happens under the lock (#place), and removes the claimed files again
  # when the change does not commit.
  class DocumentStore
    MAX_ATTEMPTS = 100
    TEMPORARY_PREFIX = ".tmp-"
    # The mode of a stored file (less the umask), as the registration uploads
    # always had it: readable by everybody on the host, like any other file
    # the app writes.
    FILE_MODE = 0o644
    # The longest name as given kept in additional_info["original_filename"]
    # (characters; a longer one is cut). A name as given has fewer than
    # UploadFilename::MAX_GIVEN_BYTES bytes, so it is a net only.
    MAX_ORIGINAL_FILENAME_LENGTH = 500

    class Error < StandardError; end

    # The upload was larger than its kind's max_upload_size_mb, else
    # Settings.documents.max_upload_size_mb; limit_mb says which.
    class TooLarge < Error
      attr_reader :limit_mb

      def initialize(message = nil, limit_mb: nil)
        super(message)
        @limit_mb = limit_mb
      end
    end

    # No free name within MAX_ATTEMPTS suffixes.
    class NameTaken < Error; end

    # A document as built, its file in a temporary file of its folder, ready
    # to be placed (#prepare, #place); attributes as given, own the lists and
    # refs as built (#follow).
    Prepared = Struct.new(:document, :temporary, :folder, :ext, :kind, :attributes, :own, keyword_init: true)
    # What a document takes from the one it follows, unless given (#follow).
    FOLLOWED = %i[readable_by writable_by deletable_by key_ref secondary_key_ref].freeze

    class << self
      def root
        configured = Settings.documents&.storage_root.presence
        Pathname(configured || HitobitoWsjrdp2027::Wagon.root.join("private", "uploads"))
      end

      def max_upload_size = Integer(Settings.documents&.max_upload_size_mb || 20) * 1.megabyte

      # The full path of a document's file. Raises ArgumentError for a
      # relative path that is absolute or leaves the root; the store writes
      # none such.
      def path_for(document)
        relative = Pathname(document.relative_storage_file_path.to_s)
        if relative.absolute? || relative.each_filename.any? { |part| part == ".." } || relative.to_s.empty?
          raise ArgumentError, "invalid relative_storage_file_path of document #{document.id}"
        end

        root.join(relative)
      end

      # Stores io as a new document and returns it, saved. attributes are the
      # document's (subject, key, key_number, secondary_key,
      # secondary_key_number, filename, author, origin, comment, ...); ext
      # names the file's extension (DocumentFilename.extension_error), else
      # the uploaded file name or the content type give it.
      #
      # - replaces: the document it follows; that one becomes superseded and
      #   the new one takes its keys and lists unless they are given.
      # - derived_from: the original of a derivation (with derivation_key);
      #   the derivation takes the original's subject, keys and lists.
      # - readable_by, writable_by, deletable_by: given (by an admin or the
      #   system) they apply; else those of the document's kind
      #   (WsjrdpDocumentKind), else the table's defaults.
      # - upload: true checks the size limit and the files the kind accepts
      #   (only uploads have them).
      # - allow_empty: an empty file (0 bytes) is refused unless true -- no
      #   PDF, no image, no letter is empty; a writer that means to keep an
      #   empty file says so.
      #
      # The block, if given, gets the document as built, before anything is
      # written (e.g. to authorize it).
      #
      # A write of its own (Wsjrdp2027::DocumentWrite): without replaces the
      # slot must be free, with it replaces must still be current. A subject
      # whose data is not valid does not refuse the document; the warning
      # goes to the log (a writer that shows it uses DocumentWrite).
      def store!(io, attributes, ext: nil, upload: true, allow_empty: false, now: Time.zone.now, &block)
        attributes = attributes.to_h.symbolize_keys
        write = DocumentWrite.new(skip_unchanged: false)
        write.put(io, attributes, ext: ext, upload: upload, allow_empty: allow_empty, now: now,
          expected_current: attributes[:replaces], &block)
        document = write.commit!.first.document
        write.warnings.each { |warning| Rails.logger.warn("DocumentStore.store! #{document.id}: #{warning}") }
        document
      end

      # Removes the temporary file of a prepared document.
      def discard(prepared)
        FileUtils.rm_f(prepared.temporary) if prepared&.temporary
      end

      # Registers a file that already lies under the root, where it lies, as
      # the current document of its slot: the current one of the slot becomes
      # superseded. A file that is not there gets file_status missing. The
      # rights come as in store!. For writers that put the file in place
      # themselves (the registration uploads, doc/wsjrdp/documents.md); under
      # the lock of the slot (DocumentWrite.lock_key).
      def register!(path, attributes, now: Time.current)
        new.register!(Pathname(path), attributes, now: now)
      end

      # Hides a document: deleted, with deleted_at; the file stays. reason
      # and who hid it (by, a person) go into additional_info. A write of its
      # own (Wsjrdp2027::DocumentWrite#hide), also for a document whose
      # subject is gone.
      def hide!(document, reason: nil, by: nil)
        DocumentWrite.new(subject: document.subject).hide(document, reason: reason, by: by).commit!
        document.reload
      end

      # Hides the current original of a slot, if there is one; answers it.
      def hide_current!(subject, reason: nil, by: nil, **slot)
        DocumentWrite.new(subject: subject).remove(reason: reason, by: by, **slot).commit!.first.document
      end

      # The current document a new one would follow: of its slot, or for a
      # derivation of its original and derivation key.
      def current_like(document)
        WsjrdpDocument.current
          .where(subject_type: document.subject_type, subject_id: document.subject_id,
            derived_from_id: document.derived_from_id || document.derived_from&.id,
            derivation_key: document.derivation_key)
          .in_slot(key: document.key, key_number: document.key_number.to_i,
            secondary_key: document.secondary_key.to_s, secondary_key_number: document.secondary_key_number.to_i)
          .first
      end

      # Marks a document deleted, as #hide! does, in the caller's
      # transaction and under the caller's locks (DocumentWrite).
      def mark_deleted!(document, reason: nil, by: nil)
        info = document.additional_info.merge({"deleted_reason" => reason, "deleted_by_id" => by&.id}.compact)
        document.update!(status: WsjrdpDocument::DELETED, deleted_at: Time.current, additional_info: info)
      end
    end

    # Builds the document and writes io into a temporary file of its folder:
    # everything but its name and row. Refuses (RecordInvalid, TooLarge)
    # before anything stays behind. The block gets the document as built,
    # before anything is written. follow_current: a document without
    # replaces follows the current one of its slot, if there is one (#follow;
    # the writer does it again under the slot's lock). An empty file is
    # refused unless allow_empty (store!).
    def prepare(io, attributes, ext:, upload:, allow_empty: false, follow_current: false)
      attributes = attributes.to_h.symbolize_keys
      document = build(attributes)
      prepared = Prepared.new(document: document, attributes: attributes,
        own: FOLLOWED.index_with { |name| document.public_send(name) })
      follow(prepared, self.class.current_like(document)) if follow_current && document.replaces.nil?
      @kind = WsjrdpDocumentKind.for_document(document)
      yield document if block_given?
      raise ActiveRecord::RecordInvalid, document if ext.present? && extension_invalid?(document, ext)
      raise ActiveRecord::RecordInvalid, document if replaces_not_current?(document)

      folder = self.class.root.join(DocumentSubjects.fetch(document.subject_type).folder_for(document.subject_id))
      FileUtils.mkdir_p(folder)
      temporary = folder.join("#{TEMPORARY_PREFIX}#{SecureRandom.hex(8)}")
      written = false
      begin
        write_temporary(io, temporary, upload)
        describe(document, temporary, ext)
        raise ActiveRecord::RecordInvalid, document if !allow_empty && empty_file?(document)
        raise ActiveRecord::RecordInvalid, document if upload && refused_by_kind?(document)
        raise ActiveRecord::RecordInvalid, document unless document.valid?

        written = true
      ensure
        FileUtils.rm_f(temporary) unless written
      end
      prepared.temporary = temporary
      prepared.folder = folder
      prepared.ext = @ext
      prepared.kind = @kind
      prepared
    end

    # Sets the document to follow current, the current one of its slot found
    # anew (nil: the slot is free): it replaces it and takes its lists and
    # refs unless the attributes give them, as a document built with replaces
    # does; in a free slot it keeps its own.
    def follow(prepared, current)
      document = prepared.document
      document.replaces = current
      FOLLOWED.each do |name|
        next unless prepared.attributes[name].nil?

        document.public_send(:"#{name}=", current ? current.public_send(name) : prepared.own[name])
      end
    end

    # Moves the prepared file to a free name of its folder -- one no file and
    # no row has -- and sets the document's paths; answers the path. Before
    # the slot's lock (DocumentWrite): file system work only.
    def claim_name(prepared, now:)
      document = prepared.document
      MAX_ATTEMPTS.times do |suffix|
        name = DocumentFilename.build(timestamp: now, suffix: suffix, subject_id: document.subject_id,
          key: document.key, key_number: document.key_number,
          secondary_key: document.secondary_key, secondary_key_number: document.secondary_key_number,
          derivation_key: document.derivation_key, ext: prepared.ext)
        path = prepared.folder.join(name)
        relative = path.relative_path_from(self.class.root).to_s
        next if WsjrdpDocument.exists?(relative_storage_file_path: relative)
        next unless reserve(path)

        move(prepared.temporary, path)
        prepared.temporary = nil
        document.absolute_storage_file_path = path.to_s
        document.relative_storage_file_path = relative
        return path
      end
      raise NameTaken, "no free name for the document within #{MAX_ATTEMPTS} suffixes"
    end

    # Saves the row of a document whose file is in place (#claim_name); the
    # predecessor (replaces) becomes superseded. Under the slot's lock
    # (DocumentWrite): database work only; answers the document.
    def place(prepared)
      save(prepared.document)
      prepared.document
    end

    def register!(path, attributes, now:)
      root = self.class.root
      unless path.to_s.start_with?("#{root}/")
        raise ArgumentError, "#{path} does not lie under the upload root"
      end

      attributes = attributes.to_h.symbolize_keys
      document = build(attributes.reverse_merge(filename: path.basename.to_s))
      document.relative_storage_file_path = path.relative_path_from(root).to_s
      document.absolute_storage_file_path = path.to_s
      document.created_at ||= now
      if path.file?
        describe(document, path, nil)
      else
        document.file_status = WsjrdpDocument::FILE_MISSING
        document.file_checked_at = Time.current
        document.content_type = Marcel::MimeType.for(name: document.filename.to_s)
      end
      key = DocumentWrite.lock_key(document.subject_type, document.subject_id, DocumentWrite.slot_of(document))
      Wsjrdp::LockedChange.run(keys: [key]) do
        document.replaces ||= current_of_slot(document)
        save(document)
      end
      document
    end

    private

    def build(attributes)
      attributes = attributes.to_h.symbolize_keys
      document = WsjrdpDocument.new(attributes.except(:replaces, :derived_from, :filename))
      inherit(document, attributes[:replaces], attributes, :replaces) if attributes[:replaces]
      inherit(document, attributes[:derived_from], attributes, :derived_from) if attributes[:derived_from]
      apply_kind_rights(document, attributes) unless attributes[:replaces] || attributes[:derived_from]
      take_filename(document, attributes[:filename]) if attributes.key?(:filename)
      document.status = WsjrdpDocument::CURRENT
      document
    end

    # The file name as given (an upload's, from the uploader's browser),
    # checked and normalized (UploadFilename): a refused one -- too long as
    # given, no valid UTF-8, a control character, U+202E, "/" or a backslash, too
    # long normalized -- refuses the document (RecordInvalid, before anything
    # is written; the error says why, not the name).
    # Nothing left: the fallback after the document's keys. A name the
    # normalizing changed goes into additional_info["original_filename"] as
    # given, at most MAX_ORIGINAL_FILENAME_LENGTH characters.
    def take_filename(document, given)
      given = given.to_s
      refuse_filename(document, given, UploadFilename.refusal(given))

      normalized = UploadFilename.normalize(given, fallback: UploadFilename.fallback_for(**DocumentWrite.slot_of(document)))
      refuse_filename(document, given, :too_long) if normalized.bytesize > UploadFilename::MAX_BYTES
      document.filename = normalized
      return if normalized == given

      original = UploadFilename.utf8(given)[0, MAX_ORIGINAL_FILENAME_LENGTH]
      document.additional_info = document.additional_info.to_h.merge("original_filename" => original)
    end

    def refuse_filename(document, given, reason)
      return unless reason

      document.errors.add(:filename, reason, **UploadFilename.error_options(given))
      raise ActiveRecord::RecordInvalid, document
    end

    # The lists not given come from the document's kind, if it has one.
    def apply_kind_rights(document, attributes)
      kind = WsjrdpDocumentKind.for_document(document)
      return unless kind

      kind.rights.each { |list, entries| document.public_send(:"#{list}=", entries) unless attributes.key?(list) }
    end

    def current_of_slot(document)
      return nil unless document.subject

      WsjrdpDocument.current_for(document.subject, key: document.key, key_number: document.key_number,
        secondary_key: document.secondary_key, secondary_key_number: document.secondary_key_number)
    end

    # The kind's restrictions on the uploaded file (WsjrdpDocumentKind#upload_error).
    def refused_by_kind?(document)
      error, options = @kind&.upload_error(content_type: document.content_type, filename: document.filename,
        byte_size: document.byte_size)
      return false unless error

      document.errors.add(:base, :"kind_#{error}", **options)
      true
    end

    INHERITED_KEYS = %i[key key_number secondary_key secondary_key_number key_ref secondary_key_ref].freeze
    INHERITED_LISTS = %i[readable_by writable_by deletable_by].freeze

    # A replacement takes the keys and lists of the document it follows
    # unless given (not nil); a derivation always takes the subject and keys
    # of its original, and its lists unless given.
    def inherit(document, other, attributes, kind)
      document.public_send(:"#{kind}=", other)
      fixed = (kind == :derived_from) ? [:subject, *INHERITED_KEYS] : []
      (fixed + INHERITED_KEYS + INHERITED_LISTS).uniq.each do |name|
        next if !fixed.include?(name) && !attributes[name].nil?

        document.public_send(:"#{name}=", other.public_send(name))
      end
    end

    def empty_file?(document)
      return false unless document.byte_size.to_i.zero?

      document.errors.add(:base, :empty_file)
      true
    end

    # Only a current document is replaced.
    def replaces_not_current?(document)
      return false if document.replaces.nil? || document.replaces.current?

      document.errors.add(:base, :replaces_not_current)
      true
    end

    def extension_invalid?(document, ext)
      error = DocumentFilename.extension_error(ext)
      document.errors.add(:base, :invalid_extension, ext: ext) if error
      error.present?
    end

    # Copies io into the temporary file; an upload above the limit -- its
    # kind's, else the general one -- is refused.
    def write_temporary(io, temporary, upload)
      limit_mb = @kind&.max_upload_size_mb
      limit = limit_mb ? limit_mb.megabytes : self.class.max_upload_size
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, FILE_MODE) do |file|
        source = io.respond_to?(:to_io) ? io.to_io : io
        source.rewind if source.respond_to?(:rewind)
        copied = upload ? IO.copy_stream(source, file, limit + 1) : IO.copy_stream(source, file)
        if upload && copied > limit
          raise TooLarge.new("the upload is larger than #{limit} bytes", limit_mb: limit / 1.megabyte)
        end
      end
    end

    # Size, checksum, content type and the extension of the file.
    def describe(document, temporary, ext)
      document.file_status = WsjrdpDocument::FILE_PRESENT
      document.file_checked_at = Time.current
      document.byte_size = File.size(temporary)
      document.content_sha256 = Digest::SHA256.file(temporary).hexdigest
      document.content_type = Marcel::MimeType.for(temporary, name: document.filename.to_s,
        declared_type: document.content_type.presence)
      @ext = ext.presence ||
        DocumentFilename.extension_from_filename(document.filename) ||
        DocumentFilename.extension_for_type(document.content_type)
    end

    # Takes path for this document: creates it empty, exclusively; false
    # when a file has the name.
    def reserve(path)
      File.open(path, File::WRONLY | File::CREAT | File::EXCL, FILE_MODE) { nil }
      true
    rescue Errno::EEXIST
      false
    end

    # Renames the temporary file onto its reserved name; the reservation goes
    # again when that fails.
    def move(temporary, path)
      File.rename(temporary, path)
    rescue
      FileUtils.rm_f(path)
      raise
    end

    # The predecessor becomes superseded in the same transaction, so the new
    # document takes its place among the current ones.
    def save(document)
      WsjrdpDocument.transaction(requires_new: true) do
        if (predecessor = document.replaces)
          predecessor.lock!
          raise ActiveRecord::RecordInvalid, document if replaces_not_current?(document)

          predecessor.update!(status: WsjrdpDocument::SUPERSEDED, superseded_at: Time.current)
        end
        document.save!
      end
    end
  end
end
