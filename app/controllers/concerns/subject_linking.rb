# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module SubjectLinking
  extend ActiveSupport::Concern

  included do
  end

  def link_subject
    authorize!(:update, entry)
    subject_id = params[:subject_id].to_i
    subject_type = params[:subject_type].to_s
    if subject_type == "Person"
      linked_subject = Person.find(subject_id)
      authorize!(:show, linked_subject)
      entry.subject = linked_subject
      entry.save!
    end
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.action(:refresh, "") }
      format.html { redirect_to entry.fin_account }
    end
  end

  def disallow_link_subject
    authorize!(:update, entry)
    subject_id = params[:subject_id].to_i
    subject_type = params[:subject_type].to_s
    entry.disallow_subject_id_and_type_candidate(subject_id, subject_type)
    entry.save!
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.action(:refresh, "") }
      format.html { redirect_to entry.fin_account }
    end
  end
end
