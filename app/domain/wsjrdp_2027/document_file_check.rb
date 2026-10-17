# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027
  # Checks whether the files of document rows are where the rows say
  # (DocumentStore.path_for), for any kind of document and any status: a row
  # whose file is gone becomes file_status missing, one whose file is back
  # present -- with its size and SHA-256, and its type if it had none
  # (DocumentFileData). Every row checked gets file_checked_at. A row with an
  # empty path, or with one the store refuses, counts as missing.
  #
  # Each folder is listed once (a stat per file is slow on some mounts).
  class DocumentFileCheck
    # One row as #check takes it.
    Row = Struct.new(:id, :relative_storage_file_path, :file_status, :filename, :content_type)

    Result = Struct.new(:checked, :missing, :back, :failed, :errors, keyword_init: true) do
      def to_h = super.merge(errors: errors.first(50))
    end

    COLUMNS = %i[id relative_storage_file_path file_status filename content_type].freeze

    # Every row, as #check takes them, oldest first.
    def self.rows = WsjrdpDocument.order(:id).pluck(*COLUMNS).map { |values| Row.new(*values) }

    attr_reader :result

    def initialize(now: Time.current)
      @now = now
      @listings = {}
      @result = Result.new(checked: 0, missing: 0, back: 0, failed: 0, errors: [])
    end

    # Checks the rows and writes what changed; the result counts them.
    def check(rows)
      unchanged = []
      rows.each do |row|
        path = path_of(row)
        status = (path && listed?(path)) ? WsjrdpDocument::FILE_PRESENT : WsjrdpDocument::FILE_MISSING
        next unchanged << row.id if status == row.file_status

        update(row, path, status)
      rescue SystemCallError, ActiveRecord::ActiveRecordError => e
        @result.failed += 1
        @result.errors << "#{row.id}: #{e.message}"
      end
      WsjrdpDocument.stamp_checked(unchanged, @now) if unchanged.any?
      @result.checked += rows.size
      @result
    end

    private

    def update(row, path, status)
      changes = {file_status: status, file_checked_at: @now, updated_at: @now}
      if status == WsjrdpDocument::FILE_PRESENT
        data = DocumentFileData.of(path, filename: row.filename)
        data.delete(:content_type) if row.content_type.present?
        changes.merge!(data)
        @result.back += 1
      else
        @result.missing += 1
      end
      WsjrdpDocument.where(id: row.id).update_all(changes)
    end

    def path_of(row)
      DocumentStore.path_for(row)
    rescue ArgumentError
      nil
    end

    def listed?(path)
      folder = path.dirname.to_s
      listing = @listings[folder] ||= begin
        Dir.children(folder).to_set
      rescue SystemCallError
        Set.new
      end
      listing.include?(path.basename.to_s)
    end
  end
end
