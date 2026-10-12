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
  # folder first, then linked to its name, which fails when the name is taken
  # (or, where the file system has no hard links, created exclusively and
  # filled). A taken name -- by a file or by a row -- gets the next suffix
  # _1, _2, ... A file whose row could not be saved is removed again; one
  # whose row an enclosing transaction rolls back later stays without a row.
  class DocumentStore
    MAX_ATTEMPTS = 100
    TEMPORARY_PREFIX = ".tmp-"
    PATH_INDEX = "index_wsjrdp_documents_on_relative_storage_file_path"
    # Errors of File.link where the file system has no hard links.
    LINK_UNSUPPORTED = [NotImplementedError, Errno::EPERM, Errno::EXDEV, Errno::EOPNOTSUPP, Errno::EMLINK].freeze

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
      #
      # The block, if given, gets the document as built, before anything is
      # written (e.g. to authorize it).
      def store!(io, attributes, ext: nil, upload: true, now: Time.zone.now, &block)
        new.store!(io, attributes, ext: ext, upload: upload, now: now, &block)
      end

      # Registers a file that already lies under the root, where it lies, as
      # the current document of its slot: the current one of the slot becomes
      # superseded. A file that is not there gets file_status missing. The
      # rights come as in store!. For writers that put the file in place
      # themselves (the registration uploads, doc/wsjrdp/documents.md).
      def register!(path, attributes, now: Time.current)
        new.register!(Pathname(path), attributes, now: now)
      end

      # Hides a document: deleted, with deleted_at; the file stays. reason
      # and who hid it (by, a person) go into additional_info.
      def hide!(document, reason: nil, by: nil)
        info = document.additional_info.merge({"deleted_reason" => reason, "deleted_by_id" => by&.id}.compact)
        document.update!(status: WsjrdpDocument::DELETED, deleted_at: Time.current, additional_info: info)
      end

      # Hides the current original of a slot, if there is one; answers it.
      def hide_current!(subject, reason: nil, by: nil, **slot)
        document = WsjrdpDocument.current_for(subject, **slot)
        hide!(document, reason: reason, by: by) if document
        document
      end
    end

    def store!(io, attributes, ext:, upload:, now:)
      document = build(attributes)
      @kind = WsjrdpDocumentKind.for_document(document)
      yield document if block_given?
      raise ActiveRecord::RecordInvalid, document if ext.present? && extension_invalid?(document, ext)
      raise ActiveRecord::RecordInvalid, document if replaces_not_current?(document)

      folder = self.class.root.join(DocumentSubjects.fetch(document.subject_type).folder_for(document.subject_id))
      FileUtils.mkdir_p(folder)
      temporary = folder.join("#{TEMPORARY_PREFIX}#{SecureRandom.hex(8)}")
      begin
        write_temporary(io, temporary, upload)
        describe(document, temporary, ext)
        raise ActiveRecord::RecordInvalid, document if upload && refused_by_kind?(document)
        raise ActiveRecord::RecordInvalid, document unless document.valid?

        save_under_free_name(document, temporary, folder, now)
      ensure
        FileUtils.rm_f(temporary)
      end
      document
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
      document.replaces ||= current_of_slot(document)
      save(document)
      document
    end

    private

    def build(attributes)
      attributes = attributes.to_h.symbolize_keys
      document = WsjrdpDocument.new(attributes.except(:replaces, :derived_from))
      inherit(document, attributes[:replaces], attributes, :replaces) if attributes[:replaces]
      inherit(document, attributes[:derived_from], attributes, :derived_from) if attributes[:derived_from]
      apply_kind_rights(document, attributes) unless attributes[:replaces] || attributes[:derived_from]
      document.status = WsjrdpDocument::CURRENT
      document
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
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o640) do |file|
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

    def save_under_free_name(document, temporary, folder, now)
      MAX_ATTEMPTS.times do |suffix|
        name = DocumentFilename.build(timestamp: now, suffix: suffix, subject_id: document.subject_id,
          key: document.key, key_number: document.key_number,
          secondary_key: document.secondary_key, secondary_key_number: document.secondary_key_number,
          derivation_key: document.derivation_key, ext: @ext)
        path = folder.join(name)
        next unless claim(temporary, path)

        document.absolute_storage_file_path = path.to_s
        document.relative_storage_file_path = path.relative_path_from(self.class.root).to_s
        saved = false
        begin
          save(document)
          saved = true
          return document
        rescue ActiveRecord::RecordNotUnique => e
          raise unless e.message.include?(PATH_INDEX)
        ensure
          FileUtils.rm_f(path) unless saved
        end
      end
      raise NameTaken, "no free name for the document within #{MAX_ATTEMPTS} suffixes"
    end

    # Puts the temporary file under path; false when path is taken.
    def claim(temporary, path)
      File.link(temporary, path)
      true
    rescue Errno::EEXIST
      false
    rescue *LINK_UNSUPPORTED
      copy_exclusively(temporary, path)
    end

    def copy_exclusively(temporary, path)
      File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o640) do |file|
        File.open(temporary, "rb") { |source| IO.copy_stream(source, file) }
      end
      true
    rescue Errno::EEXIST
      false
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
