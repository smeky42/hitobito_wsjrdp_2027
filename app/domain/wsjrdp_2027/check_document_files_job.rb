# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027
  # Checks the files of all documents in the background ("Dateien prüfen" on
  # the overview of the Dokumentenverwaltung, DocumentManagementController):
  # every row of wsjrdp_documents, whatever its kind and status
  # (DocumentFileCheck), in batches of BATCH, counting the files. A tracked
  # job (Wsjrdp::TrackedJob): queued with its log entry, with progress,
  # cancelling (between two batches) and status.
  class CheckDocumentFilesJob < Wsjrdp::TrackedJob
    self.log_category = "documents"
    self.sub_category = "document_files_check"
    self.queue_name = "documents"
    # Next to RegisterDocumentsJob's.
    self.lock_key = 2_027_000_003
    self.i18n_scope = "document_management.file_check"
    self.work_phase = "check"
    self.figures = %w[files]
    self.pace = "files"

    BATCH = 500

    private

    def prepare
      rows = DocumentFileCheck.rows
      [rows, {"files" => rows.size}]
    end

    def work(rows, progress)
      rows.each_slice(BATCH) do |batch|
        check.check(batch)
        break if progress.tick(check.result, files: batch.size) == :stop
      end
      check.result
    end

    def empty_result = check.result

    def check = @check ||= DocumentFileCheck.new
  end
end
