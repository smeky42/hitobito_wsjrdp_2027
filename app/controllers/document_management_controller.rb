# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# "Übersicht", the first tab of the Dokumentenverwaltung in Einstellungen
# (/document_management), for admins; the starting point of the area
# (Sheet::DocumentManagement). It checks the files of all documents in the
# background (Wsjrdp2027::CheckDocumentFilesJob, a tracked job):
#
# - check_files queues a check unless one waits or works;
# - check_files_progress answers its status as JSON for the progress display;
# - check_files_cancel cancels it.
class DocumentManagementController < ApplicationController
  include Wsjrdp::TrackedJobEndpoints

  I18N = "document_management.file_check"

  before_action { authorize!(:manage_documents, WsjrdpDocument) }

  helper_method :check_runs

  def index
  end

  def check_files
    enqueue_tracked_job(Wsjrdp2027::CheckDocumentFilesJob.new(current_user.id), back: document_management_path,
      texts: {enqueued: t("#{I18N}.enqueued"), running: t("#{I18N}.running")})
  end

  def check_files_progress = render_tracked_job_status(Wsjrdp2027::CheckDocumentFilesJob)

  def check_files_cancel = cancel_tracked_job(Wsjrdp2027::CheckDocumentFilesJob, back: document_management_path)

  private

  def check_runs
    @check_runs ||= Wsjrdp2027::CheckDocumentFilesJob.entries.order(created_at: :desc).limit(5)
  end
end
