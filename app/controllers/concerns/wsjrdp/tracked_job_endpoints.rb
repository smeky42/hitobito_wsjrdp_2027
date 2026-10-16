# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The controller side of a tracked job (Wsjrdp::TrackedJob): what its
# progress display (shared/wsjrdp/_tracked_job_progress) asks for and posts.
# A host calls them from its own actions, so its routes and its
# authorization stay its own:
#
#   def progress = render_tracked_job_status(Wsjrdp2027::RegisterDocumentsJob)
#   def cancel = cancel_tracked_job(Wsjrdp2027::RegisterDocumentsJob, back: some_path)
module Wsjrdp::TrackedJobEndpoints
  extend ActiveSupport::Concern

  private

  # The job's status as JSON (Wsjrdp::TrackedJob.status).
  def render_tracked_job_status(job)
    render json: job.status
  end

  # Cancels the job's run (Wsjrdp::TrackedJob.cancel!): JSON with the outcome
  # and the new status for the display, else a redirect to `back` with a
  # notice (the job's cancel.* texts, else wsjrdp.tracked_job.cancel.*).
  def cancel_tracked_job(job, back:)
    outcome = job.cancel!(by: current_user)
    respond_to do |format|
      format.json { render json: {outcome: outcome}.merge(job.status) }
      format.html do
        key = outcome || "none"
        redirect_to back, notice: t("#{job.i18n_scope}.cancel.#{key}", default: :"wsjrdp.tracked_job.cancel.#{key}")
      end
    end
  end

  # Queues a run of the job unless one waits or works; the flash says which
  # (`texts`: {enqueued:, running:}).
  def enqueue_tracked_job(job_instance, back:, texts:)
    return redirect_to(back, alert: texts.fetch(:running)) if job_instance.class.running?

    job_instance.enqueue!
    redirect_to back, notice: texts.fetch(:enqueued)
  end
end
