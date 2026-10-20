# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "digest"

module Wsjrdp2027
  # The registration uploads (people.upload_*_pdf, generated_registration_pdf)
  # as rows of wsjrdp_documents, where their files lie
  # (doc/wsjrdp/documents.md, "Registration documents").
  #
  # A chain is one person and one key: every file that column ever held,
  # oldest first. Scan builds the chains from
  # - the PaperTrail versions of the person, which say when a path was set or
  #   the column emptied, and by whom;
  # - the column as it is now;
  # - the files in the person's folder;
  # - the rows already in wsjrdp_documents (by relative path).
  # Import registers a chain: one row per file, each replacing the one before;
  # the column's file is current, an older one superseded, the last one after
  # emptying the column deleted. A file that is gone gets a row with
  # file_status missing. A registered row is checked again on every run: its
  # file_status follows the file (a file that came back gets its type, size
  # and SHA-256), and file_checked_at says when. people is never changed. The rows get the rights of
  # their kind (WsjrdpDocumentKind).
  #
  # record! and clear! keep wsjrdp_documents in step when a column is set or
  # emptied (the upload page, the generated registration PDF).
  module RegistrationDocuments
    # column => key; the key is the one the file names carry, apart from
    # older generated registration PDFs (LEGACY_FILE_KEYS).
    COLUMNS = {
      "upload_contract_pdf" => "contract",
      "upload_sepa_pdf" => "sepa",
      "upload_medical_pdf" => "medical",
      "upload_passport_pdf" => "passport",
      "upload_photo_permission_pdf" => "photo_permission",
      "upload_good_conduct_pdf" => "good_conduct",
      "upload_data_agreement_pdf" => "data_agreement",
      "upload_recommendation_pdf" => "recommendation",
      "generated_registration_pdf" => "registration_generated"
    }.freeze
    KEYS = COLUMNS.values.freeze
    # Keys older file names carry that are no valid keys any more ("-" is
    # the separator of a name's parts), with the key they stand for. New
    # files are named with the key (generated_registration_filename).
    LEGACY_FILE_KEYS = {"registration-generated" => "registration_generated"}.freeze
    UPLOADS_MARKER = "/private/uploads/"

    # Where the rows of a key without a kind get their lists from: the
    # table's defaults.
    LISTS = WsjrdpDocumentKind::LISTS

    module_function

    def key_for(people_column) = COLUMNS.fetch(people_column.to_s)

    def people_column_for(key) = COLUMNS.key(key.to_s) || raise(KeyError, "no column for #{key}")

    # The file name of a newly generated registration PDF, named like any
    # document ("2026-10-17-10-15-00--42-registration_generated.pdf").
    def generated_registration_filename(person, at: Time.zone.now)
      DocumentFilename.build(timestamp: at, subject_id: person.id, key: key_for("generated_registration_pdf"),
        ext: "pdf")
    end

    # The kinds of the keys, by key.
    def kinds = WsjrdpDocumentKind.where(subject_type: "Person", key: KEYS, secondary_key: "").index_by(&:key)

    # The lists of a new row of the key: its kind's, else the table's
    # defaults.
    def rights_for(key, kinds = self.kinds)
      kinds[key]&.rights || LISTS.index_with { |list| WsjrdpDocument.column_defaults[list.to_s] }
    end

    # Records the file a column was just set to (path as the column holds
    # it) as the current document of its key; the one before is superseded.
    # A path registered already answers its row.
    def record!(person, people_column:, path:, author: nil, origin: "ui")
      relative = relative_path(path) || (path.to_s.start_with?("person/") ? path.to_s : nil)
      raise ArgumentError, "#{path} does not lie under the upload root" unless relative

      existing = WsjrdpDocument.find_by(relative_storage_file_path: relative)
      return existing if existing

      DocumentStore.register!(DocumentStore.root.join(relative),
        {subject: person, key: key_for(people_column), author: author, origin: origin,
         additional_info: {"registration_upload" => {"column" => people_column.to_s, "source" => origin}}})
    end

    # Hides the current document of a column that was just emptied; answers
    # it, nil when there is none.
    def clear!(person, people_column:, by: nil, reason: "column_cleared")
      DocumentStore.hide_current!(person, reason: reason, by: by, key: key_for(people_column))
    end

    # The path below the upload root, nil for a path outside of it.
    def relative_path(path)
      index = path.to_s.index(UPLOADS_MARKER)
      index && path.to_s[(index + UPLOADS_MARKER.length)..]
    end

    # A path as the chains know it: below the root where it lies there, else
    # as it is.
    def path_key(path) = relative_path(path) || path.to_s

    # The versions of people (of the given ones) that touch the columns: the
    # scan reads them, Import#stale? counts them again.
    def column_versions(person_ids = nil)
      scope = ::PaperTrail::Version.where(item_type: "Person")
      scope = scope.where(item_id: person_ids) if person_ids
      scope.where("object_changes LIKE ANY (ARRAY[?])", COLUMNS.keys.map { |column| "%#{column}%" })
    end

    def time_of_name(name)
      parsed = parse_name(File.basename(name.to_s))
      parsed && Time.zone.strptime(parsed[:timestamp], DocumentFilename::TIMESTAMP_FORMAT)
    end

    # DocumentFilename.parse, reading a legacy key of a registration upload
    # ("...--791-registration-generated.pdf") as the key it stands for.
    def parse_name(name)
      name = name.to_s
      LEGACY_FILE_KEYS.each do |legacy, key|
        name = name.sub(/(--\d+-)#{Regexp.escape(legacy)}(?=\.|\z)/, "\\1#{key}")
      end
      DocumentFilename.parse(name)
    end

    # A column's lines in a version's YAML: "<column>:", "- <from>", "- <to>".
    CHANGE_FORMAT = /^(#{COLUMNS.keys.map { |column| Regexp.escape(column) }.join("|")}):\n- ?(.*)\n- ?(.*)$/
    PLAIN_PATH = %r{\A[\w/.-]+\z}

    # One file of a chain. status, superseded_at and deleted_at are what the
    # row says, or will say once registered.
    Entry = Struct.new(:relative_path, :recorded_path, :set_at, :author_type, :author_id, :source,
      :cleared_at, :cleared_by_type, :cleared_by_id, :exists, :document, :status, :superseded_at,
      :deleted_at, keyword_init: true) do
      def registered? = document.present?

      # The row says what the chain says.
      def in_sync?
        registered? && document.status == status && document.file_status == file_status
      end

      def file_status = exists ? WsjrdpDocument::FILE_PRESENT : WsjrdpDocument::FILE_MISSING

      def filename = File.basename(relative_path)
    end

    # person_name is filled in by who shows the chain (the scan reads no
    # names); version_count is how many versions of the person touched the
    # columns when the scan read them (Import#stale?).
    Chain = Struct.new(:person_id, :key, :column, :current_path, :entries, :person_name, :version_count,
      keyword_init: true) do
      def id = "#{person_id}-#{key}"

      def registered_count = entries.count(&:registered?)

      def missing_count = entries.count { |entry| !entry.exists }

      # :new (nothing registered), :partial, :complete (every file
      # registered as the chain says).
      def state
        if entries.none?(&:registered?) then :new
        elsif entries.all?(&:in_sync?) then :complete
        else
          :partial
        end
      end
    end

    # A finding the scan cannot place: a file with another name, a folder
    # without a person, a path outside the upload root, ...
    Anomaly = Struct.new(:kind, :path, :person_id, :detail, keyword_init: true)

    # The detail of a file_without_row finding, for who decides on it: the
    # key and the time of its name, its size, and the document of the person
    # with the same content (SHA-256), if there is one.
    FileWithoutRow = Data.define(:key, :named_at, :byte_size, :same_as_id) do
      def empty? = byte_size.to_i.zero?
    end

    # Builds the chains of all people, or of the given ones.
    #
    # A file of a person folder with a registration name that no version, no
    # column and no row names is not placed by itself: it may be an old
    # upload whose version was lost, or the file of a write that never
    # committed. It is a finding (file_without_row) for a person to decide
    # on -- adopt it (adopt: its relative path, for that scan; it is placed
    # by the time of its name and registered with the chain, and has a row
    # from then on) or set it aside (Quarantine). A file younger than GRACE
    # is left out: a write may be about to register it.
    class Scan
      GRACE = 10.minutes

      attr_reader :chains, :anomalies

      def initialize(root: DocumentStore.root, person_ids: nil, adopt: [], now: Time.current)
        @root = Pathname(root)
        @person_ids = person_ids&.map(&:to_i)
        @adopt = Array(adopt).map(&:to_s).to_set
        @now = now
        @anomalies = []
        @events = Hash.new { |hash, chain_key| hash[chain_key] = [] }
        @version_counts = Hash.new(0)
      end

      def run
        people = load_people
        read_versions
        read_columns(people)
        read_disk(people)
        place_unreferenced
        @chains = build_chains(people)
        attach_documents
        self
      end

      def chain(person_id, key) = chains.find { |chain| chain.person_id == person_id.to_i && chain.key == key }

      # The column's value [from, to] in a version's YAML, nil when the
      # version leaves the column alone. Only these two scalars are read, so
      # nothing else in the version needs to be loadable.
      def self.column_change(yaml, column) = column_changes(yaml)[column]

      # Every column's [from, to] in a version's YAML, in one pass.
      def self.column_changes(yaml)
        changes = {}
        yaml.to_s.scan(CHANGE_FORMAT) { |column, from, to| changes[column] = [scalar(from), scalar(to)] }
        changes
      end

      # A path as YAML writes it: plain or in double quotes without escapes
      # as it is, anything else through YAML.
      def self.scalar(text)
        text = text.to_s.strip
        return nil if text.empty? || text == "~" || text == "null"
        return text[1..-2] if text.length > 1 && text.start_with?('"') && text.end_with?('"') && !text.include?("\\")
        return text if text.match?(PLAIN_PATH)

        value = YAML.safe_load(text)
        value.is_a?(String) ? value : nil
      rescue Psych::Exception
        nil
      end

      # A registration upload's name: <timestamp>--<id>-<key>.pdf, nothing else.
      def self.registration_name?(parsed)
        parsed.present? && KEYS.include?(parsed[:key]) && parsed[:ext] == "pdf" && parsed[:suffix].zero? &&
          parsed[:key_number].zero? && parsed[:secondary_key] == "" && parsed[:secondary_key_number].zero? &&
          parsed[:derivation_key].nil?
      end

      def self.time_or_epoch(path) = RegistrationDocuments.time_of_name(path) || Time.zone.at(0)

      private

      # id => column => path, of the people asked for.
      def load_people
        scope = ::Person.all
        scope = scope.where(id: @person_ids) if @person_ids
        scope.pluck(:id, *COLUMNS.keys).to_h { |id, *paths| [id, COLUMNS.keys.zip(paths).to_h] }
      end

      # Every version of a person that changed one of the columns, in the
      # order they were made.
      def read_versions
        rows = RegistrationDocuments.column_versions(@person_ids).order(:created_at, :id)
          .pluck(:item_id, :object_changes, :whodunnit, :whodunnit_type, :created_at)
        rows.each_with_index do |(person_id, yaml, whodunnit, whodunnit_type, at), sequence|
          @version_counts[person_id] += 1
          author = [whodunnit_type.presence || "Person", whodunnit.presence&.to_i]
          self.class.column_changes(yaml).each do |column, (from, to)|
            if to.present?
              add_event(person_id, COLUMNS[column], :set, to, at, author, :version, sequence)
            elsif from.present?
              add_event(person_id, COLUMNS[column], :clear, from, at, author, :version, sequence)
            end
          end
        end
      end

      # A column's file not set by any version gets the time of its name.
      def read_columns(people)
        people.each do |person_id, paths|
          COLUMNS.each do |column, key|
            path = paths[column].presence
            next unless path
            next if set_paths(person_id, key).include?(path_key(path))

            add_event(person_id, key, :set, path, self.class.time_or_epoch(path), [nil, nil], :column, -1)
          end
        end
      end

      # The files of the person folders; one not set by any version or
      # column gets the time of its name.
      def read_disk(people)
        base = @root.join("person", "pdf")
        return unless base.directory?

        @disk_files = {}
        disk_entries(base).group_by { |entry| entry.split("/", 2).first }.each do |folder, entries|
          next anomaly(:folder_name, "person/pdf/#{folder}") unless folder.match?(/\A\d+\z/)

          entries.each do |entry|
            relative = "person/pdf/#{entry}"
            @disk_files[relative] = true
            read_file(people, folder.to_i, relative)
          end
        end
      end

      # "<folder>/<name>" of everything in the person folders, hidden files
      # included, in one listing (a stat per file is slow on some mounts).
      def disk_entries(base)
        patterns = @person_ids ? @person_ids.map { |id| "#{id}/*" } : ["*/*"]
        Dir.glob(patterns, File::FNM_DOTMATCH, base: base.to_s)
          .reject { |entry| entry.split("/").intersect?(%w[. ..]) }
      end

      def read_file(people, person_id, relative)
        name = File.basename(relative)
        return anomaly(:temporary_file, relative, person_id) if name.start_with?(DocumentStore::TEMPORARY_PREFIX)

        parsed = RegistrationDocuments.parse_name(name)
        return (@other_files ||= []) << [relative, person_id] unless self.class.registration_name?(parsed)
        return anomaly(:other_person, relative, person_id, parsed[:subject_id]) if parsed[:subject_id] != person_id
        return anomaly(:folder_without_person, relative, person_id) unless people.key?(person_id)
        return if set_paths(person_id, parsed[:key]).include?(relative)

        (@unreferenced ||= []) << [person_id, parsed[:key], relative]
      end

      # The files read_file found no version and no column for: placed by
      # the time of their name when a row has them or they are adopted; a
      # finding otherwise, unless younger than GRACE.
      def place_unreferenced
        list = Array(@unreferenced)
        return if list.empty?

        rows = WsjrdpDocument.where(relative_storage_file_path: list.map(&:last)).pluck(:relative_storage_file_path).to_set
        list.each do |person_id, key, relative|
          if rows.include?(relative) || @adopt.include?(relative)
            add_event(person_id, key, :set, relative, self.class.time_or_epoch(relative), [nil, nil], :disk, -1)
          else
            file_without_row(person_id, key, relative)
          end
        end
      end

      def file_without_row(person_id, key, relative)
        path = @root.join(relative)
        return if path.mtime > @now - GRACE

        sha = Digest::SHA256.file(path).hexdigest
        same_as = WsjrdpDocument.where(subject_type: "Person", subject_id: person_id, content_sha256: sha).order(:id).pick(:id)
        anomaly(:file_without_row, relative, person_id,
          FileWithoutRow.new(key: key, named_at: RegistrationDocuments.time_of_name(relative), byte_size: path.size,
            same_as_id: same_as))
      rescue Errno::ENOENT
        nil
      end

      def add_event(person_id, key, kind, path, at, author, source, sequence)
        relative = RegistrationDocuments.relative_path(path) || (path.to_s.start_with?("person/") ? path.to_s : nil)
        return anomaly(:outside_root, path.to_s, person_id, key) unless relative

        @events[[person_id.to_i, key]] << {kind: kind, relative: relative, recorded: path.to_s, at: at,
                                           author: author, source: source, sequence: sequence}
      end

      # Looks only: a key without events gets no (empty) chain from it.
      def set_paths(person_id, key)
        @events.fetch([person_id.to_i, key], []).select { |event| event[:kind] == :set }.pluck(:relative)
      end

      def path_key(path) = RegistrationDocuments.path_key(path)

      def anomaly(kind, path, person_id = nil, detail = nil)
        @anomalies << Anomaly.new(kind: kind, path: path, person_id: person_id, detail: detail)
        nil
      end

      def build_chains(people)
        @events.filter_map do |(person_id, key), events|
          paths = people[person_id]
          next anomaly(:person_missing, events.first[:relative], person_id, key) unless paths

          entries = entries_of(events)
          current = paths[COLUMNS.key(key)].presence&.then { |path| path_key(path) }
          plan_statuses(entries, current)
          Chain.new(person_id: person_id, key: key, column: COLUMNS.key(key),
            current_path: current, entries: entries, version_count: @version_counts[person_id])
        end.sort_by { |chain| [chain.person_id, KEYS.index(chain.key)] }
      end

      # One entry per path, in the order the paths were set; setting a path
      # again moves it to the end.
      def entries_of(events)
        entries = []
        events.sort_by { |event| [event[:at], event[:sequence]] }.each do |event|
          entry = entries.find { |candidate| candidate.relative_path == event[:relative] }
          if event[:kind] == :clear
            clear(entry || entries.last, event)
            next
          end

          if entry
            entries.delete(entry)
            entry.cleared_at = entry.cleared_by_type = entry.cleared_by_id = nil
          else
            entry = Entry.new(relative_path: event[:relative], recorded_path: event[:recorded], set_at: event[:at],
              author_type: event[:author][0], author_id: event[:author][1], source: event[:source])
          end
          entries << entry
        end
        entries.each { |entry| entry.exists = @disk_files&.key?(entry.relative_path) || @root.join(entry.relative_path).file? }
        entries
      end

      def clear(entry, event)
        return unless entry

        entry.cleared_at = event[:at]
        entry.cleared_by_type, entry.cleared_by_id = event[:author]
      end

      # The column's file is current; one followed by another superseded
      # when the next was set; the last one deleted when the column was
      # emptied (or no longer names it).
      def plan_statuses(entries, current)
        entries.each_with_index do |entry, index|
          following = entries[index + 1]
          if entry.relative_path == current
            entry.status = WsjrdpDocument::CURRENT
          elsif following
            entry.status = WsjrdpDocument::SUPERSEDED
            entry.superseded_at = following.set_at
          else
            entry.status = WsjrdpDocument::DELETED
            entry.deleted_at = entry.cleared_at
          end
        end
      end

      def attach_documents
        paths = chains.flat_map { |chain| chain.entries.map(&:relative_path) }
        documents = paths.each_slice(5000).flat_map do |slice|
          WsjrdpDocument.where(relative_storage_file_path: slice).to_a
        end.index_by(&:relative_storage_file_path)
        chains.each { |chain| chain.entries.each { |entry| entry.document = documents[entry.relative_path] } }
        known = documents.keys.to_set
        registered = WsjrdpDocument.where(relative_storage_file_path: Array(@other_files).map(&:first))
          .pluck(:relative_storage_file_path).to_set
        Array(@other_files).each do |relative, person_id|
          anomaly(:unexpected_name, relative, person_id) unless known.include?(relative) || registered.include?(relative)
        end
      end
    end

    # Registers chains (Scan) as rows of wsjrdp_documents with the rights of
    # their kinds (rights_for); updates the status of rows registered before.
    # Each chain in a transaction of its own, under the lock of its slot
    # (DocumentWrite.lock_key); a chain whose basis changed since the scan is
    # skipped (#stale?).
    class Import
      Result = Struct.new(:chains, :created, :updated, :failed, :skipped, :errors, keyword_init: true) do
        def to_h = super.merge(errors: errors.first(50))
      end

      # reviewed_by, reviewed_paths: who adopted the files of these relative
      # paths (Scan, adopt:) -- noted in their rows' additional_info.
      def initialize(root: DocumentStore.root, now: Time.current, reviewed_by: nil, reviewed_paths: [])
        @kinds = RegistrationDocuments.kinds
        @root = Pathname(root)
        @now = now
        @reviewed_by = reviewed_by
        @reviewed_paths = Array(reviewed_paths).map(&:to_s).to_set
        @result = Result.new(chains: 0, created: 0, updated: 0, failed: 0, skipped: 0, errors: [])
      end

      # Rows stamped per statement by #checked: a statement over a thousand
      # rows is done in a few milliseconds, so a writer that waits for one of
      # its rows waits no longer than that.
      STAMP_SLICE = 1000

      # Notes that the files of chains registered as they stand were checked
      # now (the scan found them as their rows say): file_checked_at of their
      # rows, STAMP_SLICE rows per statement, leaving out a row someone writes
      # at that moment (WsjrdpDocument.stamp_checked).
      def checked(chains)
        ids = chains.flat_map { |chain| chain.entries.filter_map { |entry| entry.document&.id } }
        ids.each_slice(STAMP_SLICE) { |slice| WsjrdpDocument.stamp_checked(slice, @now) }
      end

      # Registers the chains in order; the block, if given, gets each chain and
      # the result so far once the chain is done (a progress display) and
      # stops the run by answering :stop -- between two chains, each of which
      # is registered whole or not at all.
      def register(chains)
        chains.each do |chain|
          register_chain(chain)
          break if block_given? && yield(chain, @result) == :stop
        end
        @result
      end

      private

      # Registers the chain under its lock, unless its basis changed since
      # the scan (#stale?) -- or a file the scan found is gone by the time it
      # is read: then nothing is written, and the next run takes the chain as
      # it is by then. The files are read and hashed before the lock
      # (#file_data); under it only the rows are written.
      def register_chain(chain)
        key = DocumentWrite.lock_key("Person", chain.person_id, {key: chain.key})
        data = file_data(chain)
        registered = data && Wsjrdp::LockedChange.run(keys: [key]) do
          next false if stale?(chain)

          previous = nil
          chain.entries.each do |entry|
            file = data[entry.relative_path]
            previous = entry.document ? update(entry, previous, file) : create(chain, entry, previous, file)
          end
          true
        end
        if registered
          @result.chains += 1
        else
          @result.skipped += 1
        end
      rescue ActiveRecord::ActiveRecordError => e
        @result.failed += 1
        @result.errors << "#{chain.id}: #{e.message}"
        chain.entries.each { |entry| entry.document = nil if entry.document&.new_record? }
      end

      # Whether the chain's basis changed since the scan read it: the column
      # as it is now, how many versions of the person touch the columns, an
      # adopted file no longer there, or the rows of the chain's files -- one
      # changed (updated_at), or one for a file the scan found none for.
      def stale?(chain)
        column = ::Person.where(id: chain.person_id).pick(chain.column).presence
        return true if column&.then { |path| RegistrationDocuments.path_key(path) } != chain.current_path
        return true if RegistrationDocuments.column_versions(chain.person_id).count != chain.version_count

        # An adopted file set aside in the meantime (Quarantine, under the same lock).
        set_aside = chain.entries.any? do |entry|
          @reviewed_paths.include?(entry.relative_path) && !entry.document && !@root.join(entry.relative_path).file?
        end
        return true if set_aside

        rows = WsjrdpDocument.where(relative_storage_file_path: chain.entries.map(&:relative_path))
          .pluck(:relative_storage_file_path, :id, :updated_at).to_h { |path, id, at| [path, [id, at]] }
        chain.entries.any? do |entry|
          row = rows[entry.relative_path]
          entry.document ? row != [entry.document.id, entry.document.updated_at] : !row.nil?
        end
      end

      # The file attributes the chain's rows get (#file_attributes: type,
      # size, SHA-256), by relative path: of every file without a row, and of
      # a file whose status changed since its row was written. nil when a
      # file the scan found is gone now (set aside, deleted).
      def file_data(chain)
        chain.entries.each_with_object({}) do |entry, data|
          next if entry.document && entry.document.file_status == entry.file_status

          data[entry.relative_path] = file_attributes(entry, @root.join(entry.relative_path))
        end
      rescue Errno::ENOENT
        nil
      end

      def update(entry, previous, file)
        document = entry.document
        changes = {}
        if document.status != entry.status
          # A new status brings its times, as a new row gets them: a
          # document current again is neither superseded nor deleted.
          changes[:status] = entry.status
          changes[:superseded_at] = entry.superseded_at
          changes[:deleted_at] = (entry.status == WsjrdpDocument::DELETED) ? (entry.deleted_at || @now) : nil
        end
        changes[:replaces_id] = previous.id if previous && document.replaces_id.nil? && previous.id != document.id
        if document.file_status != entry.file_status
          changes[:file_status] = entry.file_status
          changes.merge!(file) if entry.exists
        end
        # Checked now, also when nothing else changes; only a change counts.
        @result.updated += 1 if changes.any?
        changes[:updated_at] = @now if changes.any?
        document.update_columns(changes.merge(file_checked_at: @now))
        document
      end

      def create(chain, entry, previous, file)
        document = WsjrdpDocument.new(attributes(chain, entry, previous, file))
        document.save!
        entry.document = document
        @result.created += 1
        document
      end

      def attributes(chain, entry, previous, file)
        {subject_type: "Person", subject_id: chain.person_id, key: chain.key, filename: entry.filename,
         relative_storage_file_path: entry.relative_path, absolute_storage_file_path: entry.recorded_path,
         status: entry.status, superseded_at: entry.superseded_at,
         deleted_at: (entry.deleted_at || @now if entry.status == WsjrdpDocument::DELETED),
         replaces_id: previous&.id, origin: "import", created_at: entry.set_at, updated_at: @now,
         author_type: entry.author_type, author_id: entry.author_id,
         file_status: entry.file_status, file_checked_at: @now,
         additional_info: {"registration_upload" => provenance(chain, entry)}}
          .merge(file)
          .merge(RegistrationDocuments.rights_for(chain.key, @kinds))
      end

      def file_attributes(entry, path)
        return {content_type: Marcel::MimeType.for(name: entry.filename), byte_size: nil} unless entry.exists

        DocumentFileData.of(path, filename: entry.filename)
      end

      def provenance(chain, entry)
        reviewed = @reviewed_by && @reviewed_paths.include?(entry.relative_path)
        {"column" => chain.column, "source" => entry.source.to_s,
         "cleared_by" => entry.cleared_by_id && {"type" => entry.cleared_by_type, "id" => entry.cleared_by_id},
         "reviewed_by" => reviewed ? {"type" => "Person", "id" => @reviewed_by.id} : nil,
         "reviewed_at" => reviewed ? @now.iso8601 : nil}.compact
      end
    end

    # Sets a file of a person folder aside: moves it below QUARANTINE, out of
    # the folders the scan reads, with a note of where it lay, what it was
    # and who set it aside (<name>.json beside it), and logs it for the
    # person. Nothing is deleted; moving the file back undoes it. For the
    # files no version, column or row names (Scan, file_without_row).
    #
    # The note is written first, beside its place; the file and the note are
    # then moved under the lock of the slot (DocumentWrite.lock_key), once it
    # is checked that the file is still there and has no row -- an adoption
    # (Import, under the same lock) may have come first. Gone otherwise, and
    # nothing is moved.
    class Quarantine
      QUARANTINE = "quarantine"

      # The file is no longer one to set aside: gone, or a row has it.
      class Gone < StandardError; end

      def initialize(root: DocumentStore.root, now: Time.current)
        @root = Pathname(root)
        @now = now
      end

      # Answers the path the file lies at now.
      def set_aside!(relative, person_id:, key:, by:)
        source = @root.join(relative)
        raise Gone, relative unless source.file?

        target = free_target(@root.join(QUARANTINE, relative))
        FileUtils.mkdir_p(target.dirname)
        note = {"from" => relative, "person_id" => person_id, "key" => key, "byte_size" => source.size,
                "sha256" => Digest::SHA256.file(source).hexdigest,
                "set_aside_by" => {"type" => "Person", "id" => by.id}, "set_aside_at" => @now.iso8601}
        pending = target.dirname.join("#{DocumentStore::TEMPORARY_PREFIX}#{SecureRandom.hex(8)}.json")
        pending.write(JSON.pretty_generate(note))
        move(source, target, pending, relative, person_id, key)
        log(note, target, person_id)
        target
      ensure
        FileUtils.rm_f(pending) if pending
      end

      private

      def move(source, target, pending, relative, person_id, key)
        Wsjrdp::LockedChange.run(keys: [DocumentWrite.lock_key("Person", person_id, {key: key})]) do
          raise Gone, relative unless source.file? && !WsjrdpDocument.exists?(relative_storage_file_path: relative)

          File.rename(source, target)
          begin
            File.rename(pending, "#{target}.json")
          rescue
            File.rename(target, source)
            raise
          end
        end
      end

      # The name below QUARANTINE, with a number when it is taken.
      def free_target(path)
        return path unless path.exist? || Pathname("#{path}.json").exist?

        (1..).lazy.map { |n| Pathname("#{path}.#{n}") }.find { |candidate| !candidate.exist? }
      end

      def log(note, target, person_id)
        ::HitobitoLogEntry.categories |= [RegisterDocumentsJob.log_category]
        ::HitobitoLogEntry.create!(category: RegisterDocumentsJob.log_category, level: "info",
          subject_type: "Person", subject_id: person_id,
          message: I18n.t("document_management.registration_documents.set_aside.log", path: note["from"]),
          payload: note.merge("sub_category" => "registration_documents_set_aside",
            "to" => target.relative_path_from(@root).to_s))
      end
    end
  end
end
