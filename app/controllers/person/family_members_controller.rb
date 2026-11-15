# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# A person's family links (FamilyMember) on a page of their own
# (/people/:person_id/family_members/edit), with the same rows as the person
# form (people/_family_members_fields). For whoever may edit them
# (:update_family): the privileged view and the unit leaders of the person's
# unit -- who may not edit the rest of the person form's privileged fields.
class Person::FamilyMembersController < ApplicationController
  include Wsjrdp2027::Concerns::FamilyMembersParams

  FAMILY_MEMBER_ATTRS = [:id, :kind, :other_id, :label, :inverse_label, :_destroy].freeze

  # The sheet and its left nav read @person and @group.
  before_action :person, :group
  before_action :authorize_action

  helper_method :person, :group

  def edit
  end

  def update
    attributes = params.require(:person).permit(family_members_attributes: FAMILY_MEMBER_ATTRS)
    person.family_members_attributes =
      without_protected_family_members(person, attributes[:family_members_attributes])&.to_h || {}
    if person.save
      redirect_to helpers.person_base_path(group, person), notice: "Familienmitglieder gespeichert."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def person = @person ||= Person.find(params[:person_id])

  def group = @group ||= person.default_group

  def authorize_action
    authorize!(:update_family, person)
  end
end
