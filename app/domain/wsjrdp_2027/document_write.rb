# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027
  # A change to the documents of one subject, all of it or nothing
  # (doc/wsjrdp/documents.md, "Writing documents"):
  #
  #   write = Wsjrdp2027::DocumentWrite.new(subject: person, by: current_user, origin: "ui")
  #   write.put(upload, {key: "contract", filename: upload.original_filename}, expected_current: id)
  #   write.remove(key: "sepa", reason: "deleted_by_user")
  #   write.on_subject { |person, results| ... }  # status, tags, times
  #   results = write.commit!
  #
  # commit! first writes every file to a temporary file and checks it
  # (DocumentStore#prepare) -- a refused one refuses the whole change before
  # anything is written. Then, in one transaction (Wsjrdp::LockedChange)
  # under the lock of every slot it touches, it reads each slot's current
  # document anew, links the files to their names and saves their rows, the
  # predecessors becoming superseded, hides what is removed, writes the path
  # of each slot's current document into the people column of its kind
  # (WsjrdpDocumentKind#people_column_name), runs the on_subject block and
  # saves the subject (its PaperTrail version with it). Every put and
  # remove, and a change with an on_subject block, locks the subject's row
  # first, so that what it reads of the subject -- other slots' columns,
  # status, tags -- is not stale, and a subject being destroyed refuses the
  # change (RecordNotFound once its row is gone); a hide locks the row only
  # when its kind has a people column. The files of a change that rolls
  # back are removed again.
  #
  # expected_current: :any (default) follows whatever is current -- the new
  # document replaces it and takes its lists and refs unless given
  # (DocumentStore#follow); nil expects the slot to be free, a document (or
  # id) expects it to be current (otherwise RecordInvalid with slot_taken or
  # replaces_not_current, or Conflict for a removal).
  #
  # A file equal to the slot's current one (sha256) adds nothing unless
  # skip_unchanged is false: its result is UNCHANGED.
  #
  # invalid_subject: :warn (default) saves a subject that fails its
  # validations without them and adds a warning (#warnings): the documents
  # must not depend on the rest of the subject's data, e.g. an upload for a
  # person whose record in the database is not valid still writes the
  # document and the people column. :raise lets such a subject stop the
  # change.
  #
  # An on_subject block stops the change with an error of its own
  # (Conflict, RecordInvalid, ...), which commit! passes on; one that raises
  # ActiveRecord::Rollback gets RolledBack from commit! -- the change is
  # undone either way, its files removed.
  class DocumentWrite
    LOCK_NAMESPACE = "wsjrdp_documents"

    STORED = :stored
    UNCHANGED = :unchanged
    REMOVED = :removed
    NOT_PRESENT = :not_present
    ANY = :any

    # outcome: STORED (document: the new one), UNCHANGED (the current one it
    # equals), REMOVED (the one hidden), NOT_PRESENT (nothing to remove).
    Result = Data.define(:slot, :outcome, :document)

    # Several puts were refused before anything was written; failures are
    # [[attributes, error], ...]. One refused put raises its own error.
    class Invalid < DocumentStore::Error
      attr_reader :failures

      def initialize(failures)
        @failures = failures
        super(failures.map { |_, error| error.message }.join("; "))
      end
    end

    # The on_subject block raised ActiveRecord::Rollback: the change is
    # undone, its files removed. Stop a change with an error of its own
    # instead.
    class RolledBack < DocumentStore::Error
      def initialize(message = "the change was rolled back by its on_subject block")
        super
      end
    end

    # A removal found another current document than the one expected.
    class Conflict < DocumentStore::Error
      attr_reader :slot

      def initialize(slot)
        @slot = slot
        super("the current document of #{slot} is not the one expected")
      end
    end

    # The slot of a document: its keys and numbers (a derivation has those of
    # its original).
    def self.slot_of(document)
      {key: document.key, key_number: document.key_number.to_i, secondary_key: document.secondary_key.to_s,
       secondary_key_number: document.secondary_key_number.to_i}
    end

    # The advisory lock key of a slot (Wsjrdp::LockedChange).
    def self.lock_key(subject_type, subject_id, slot)
      [LOCK_NAMESPACE, subject_type.to_s, subject_id.to_i, slot[:key].to_s, slot[:key_number].to_i,
        slot[:secondary_key].to_s, slot[:secondary_key_number].to_i].to_json
    end

    # by and origin: the author and origin of every stored document unless
    # its attributes give them.
    INVALID_SUBJECT = %i[raise warn].freeze

    # What the subject's save had to say: messages for the user.
    attr_reader :warnings

    def initialize(subject: nil, by: nil, origin: nil, skip_unchanged: true, invalid_subject: :warn,
      timeout: Wsjrdp::LockedChange::DEFAULT_TIMEOUT)
      raise ArgumentError, "invalid_subject: #{invalid_subject.inspect}" unless INVALID_SUBJECT.include?(invalid_subject)

      @invalid_subject = invalid_subject
      @warnings = []
      @subject = subject
      @by = by
      @origin = origin
      @skip_unchanged = skip_unchanged
      @timeout = timeout
      @operations = []
    end

    # Stores io as the new current document of its slot (DocumentStore.store!
    # for attributes, ext and upload). The block gets the document as built.
    def put(io, attributes, ext: nil, upload: true, now: Time.zone.now, expected_current: ANY, &block)
      attributes = attributes.to_h.symbolize_keys
      attributes = attributes.reverse_merge(subject: @subject) if @subject
      attributes = attributes.reverse_merge(author: @by) if @by
      attributes = attributes.reverse_merge(origin: @origin) if @origin
      @operations << {type: :put, io: io, attributes: attributes, ext: ext, upload: upload, now: now,
                      expected: expected_current, block: block}
      self
    end

    # Hides the current original of a slot, if there is one.
    def remove(key:, key_number: 0, secondary_key: "", secondary_key_number: 0, reason: nil, by: @by,
      expected_current: ANY)
      slot = {key: key, key_number: key_number, secondary_key: secondary_key.to_s,
              secondary_key_number: secondary_key_number}
      @operations << {type: :remove, slot: slot, reason: reason, by: by, expected: expected_current}
      self
    end

    # Hides one document, current or not -- also one whose subject is gone.
    def hide(document, reason: nil, by: @by)
      @operations << {type: :hide, document: document, slot: self.class.slot_of(document), reason: reason, by: by}
      self
    end

    # Runs under the locks, after the documents are written, before the
    # subject is saved: gets the subject (locked, fresh) and the results.
    def on_subject(&block)
      @on_subject = block
      self
    end

    # Answers the Results, in the order of the operations.
    def commit!
      @warnings = []
      prepare_all
      type, id, subject = subject!
      lock_subject = @on_subject.present? || @operations.any? { |op| op[:type] != :hide || people_column(subject, op) }
      placed = []
      keys = @operations.map { |op| self.class.lock_key(type, id, slot(op)) }
      committed = Wsjrdp::LockedChange.run(rows: lock_subject ? [subject] : [], keys: keys, timeout: @timeout) do |change|
        change.on_rollback { placed.each { |path| FileUtils.rm_f(path) } }
        results = @operations.map { |op| apply(subject, op, placed) }
        mirror(subject)
        @on_subject&.call(subject, results)
        # Always with an on_subject block: a change of tags is no attribute change.
        save_subject(subject) if @on_subject || (lock_subject && subject.has_changes_to_save?)
        results
      end
      raise RolledBack if committed.nil?

      committed
    ensure
      @operations.each { |op| DocumentStore.discard(op[:prepared]) }
    end

    private

    # The files and checks of every put; a refused one refuses all.
    def prepare_all
      failures = []
      @operations.each do |op|
        next unless op[:type] == :put

        op[:store] = DocumentStore.new
        op[:prepared] = op[:store].prepare(op[:io], op[:attributes], ext: op[:ext], upload: op[:upload],
          follow_current: !op[:expected].nil?, &op[:block])
      rescue ActiveRecord::RecordInvalid, DocumentStore::TooLarge => e
        failures << [op[:attributes], e]
      end
      return if failures.empty?

      @operations.each { |op| DocumentStore.discard(op[:prepared]) }
      raise failures.first.last if @operations.size == 1

      raise Invalid, failures
    end

    # The subject of the change: its type and id, and its record -- nil
    # when it is gone, which only a hide allows (no row lock, no people
    # column then). All operations belong to one subject.
    def subject!
      documents = @operations.filter_map { |op| op[:prepared]&.document || op[:document] }
      subject = @subject || documents.filter_map(&:subject).first
      first = documents.first
      type, id = subject ? [subject.class.base_class.name, subject.id] : [first&.subject_type, first&.subject_id]
      raise ArgumentError, "a document write needs a subject" unless type && id
      if subject.nil? && (@on_subject || @operations.any? { |op| op[:type] != :hide })
        raise ArgumentError, "a document write needs the subject's record, unless it only hides"
      end
      if documents.any? { |document| document.subject_type != type || document.subject_id != id }
        raise ArgumentError, "a document write changes the documents of one subject"
      end

      [type, id, subject]
    end

    def slot(op) = op[:slot] || self.class.slot_of(op[:prepared].document)

    # A subject that is not valid -- e.g. as it lies in the database -- does
    # not stop the documents (invalid_subject: :warn, the default): it is
    # saved without validations, so that its people columns name the files
    # just written, and the change warns instead of failing.
    def save_subject(subject)
      return subject.save! if @invalid_subject == :raise || subject.valid?

      @warnings << I18n.t("wsjrdp.document_write.subject_invalid",
        errors: subject.errors.full_messages.to_sentence)
      subject.save!(validate: false)
    end

    def apply(subject, op, placed)
      case op[:type]
      when :put then apply_put(op, placed)
      when :remove then apply_remove(subject, op)
      when :hide then apply_hide(op)
      end
    end

    def apply_put(op, placed)
      document = op[:prepared].document
      current = DocumentStore.current_like(document)
      check_expected!(document, current, op[:expected])
      if @skip_unchanged && unchanged?(current, document)
        return Result.new(slot: slot(op), outcome: UNCHANGED, document: current)
      end

      op[:store].follow(op[:prepared], current)
      op[:store].place(op[:prepared], now: op[:now])
      placed << document.absolute_storage_file_path
      Result.new(slot: slot(op), outcome: STORED, document: document)
    end

    def apply_remove(subject, op)
      current = WsjrdpDocument.current_for(subject, **op[:slot])
      if op[:expected] != ANY && current&.id != expected_id(op[:expected])
        raise Conflict, op[:slot]
      end
      return Result.new(slot: op[:slot], outcome: NOT_PRESENT, document: nil) unless current

      DocumentStore.mark_deleted!(current, reason: op[:reason], by: op[:by])
      Result.new(slot: op[:slot], outcome: REMOVED, document: current)
    end

    def apply_hide(op)
      document = op[:document].reload
      DocumentStore.mark_deleted!(document, reason: op[:reason], by: op[:by]) unless document.status == WsjrdpDocument::DELETED
      Result.new(slot: op[:slot], outcome: REMOVED, document: document)
    end

    def check_expected!(document, current, expected)
      return if expected == ANY
      return if current&.id == expected_id(expected)

      document.errors.add(:base, expected ? :replaces_not_current : :slot_taken)
      raise ActiveRecord::RecordInvalid, document
    end

    def expected_id(expected) = expected.respond_to?(:id) ? expected.id : expected

    def unchanged?(current, document)
      current.present? && !current.file_missing? && current.content_sha256.present? &&
        current.content_sha256 == document.content_sha256
    end

    # The people column of the kind of the operation's slot, for an original
    # without numbers of a person; nil when there is none.
    def people_column(subject, op)
      return nil unless subject.is_a?(::Person)

      slot = slot(op)
      return nil unless slot[:key_number].zero? && slot[:secondary_key_number].zero?
      document = op[:prepared]&.document || op[:document]
      return nil if document && (document.derived_from_id || document.derived_from)

      column = WsjrdpDocumentKind.for(subject_type: subject.class.base_class.name, key: slot[:key],
        secondary_key: slot[:secondary_key])&.people_column_name
      column if column.present? && subject.has_attribute?(column)
    end

    # The path of each touched slot's current document into its column.
    def mirror(subject)
      @operations.each do |op|
        column = people_column(subject, op)
        next unless column

        current = WsjrdpDocument.current_for(subject, **slot(op))
        subject[column] = current&.absolute_storage_file_path
      end
    end
  end
end
