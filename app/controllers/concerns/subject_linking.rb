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

  # Both actions write on behalf of a person -- linking makes the transaction
  # theirs, refusing a candidate decides about them -- so each needs :update on
  # the transaction AND on the person, exactly what the buttons are offered for
  # (Fin::SubjectLinkingHelper#may_link_subject?). Only people can be linked; any
  # other subject_type is a malformed request.
  def link_subject
    authorize!(:update, entry)
    assign_linked_subject(entry, linkable_person)
    entry.save!
    respond_after_subject_link
  end

  def disallow_link_subject
    authorize!(:update, entry)
    entry.disallow_subject_candidate(linkable_person)
    entry.save!
    respond_after_subject_link
  end

  private

  # Sets the person on the transaction. A controller whose transaction records
  # the provenance of that link overrides this (Fin::MossBookingsController).
  def assign_linked_subject(tx, person)
    tx.subject = person
  end

  def linkable_person
    raise ActionController::BadRequest, "subject_type must be Person" unless params[:subject_type].to_s == "Person"

    Person.find(params[:subject_id].to_i).tap { |person| authorize!(:update, person) }
  end

  # The answer after a link action. Default: refresh the page (Turbo Stream) or
  # go back to the account. A controller whose page can show the change in one
  # element overrides this (Fin::MossBookingsController replaces the row's
  # description block).
  def respond_after_subject_link
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.action(:refresh, "") }
      format.html { redirect_to entry.fin_account }
    end
  end
end
