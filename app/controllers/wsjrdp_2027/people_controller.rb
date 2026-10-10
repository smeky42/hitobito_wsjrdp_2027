# frozen_string_literal: true

#  Copyright (c) 2025, 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027::PeopleController
  WSJRDP_ALWAYS_PERMITTED_ATTRS = [
    :rdp_association,
    :rdp_association_region,
    :rdp_association_sub_region,
    :rdp_association_group,
    :rdp_association_number,
    :buddy_id,
    :buddy_id_ul,
    :buddy_id_yp,
    :additional_contact_name_a,
    :additional_contact_adress_a,
    :additional_contact_email_a,
    :additional_contact_phone_a,
    :additional_contact_name_b,
    :additional_contact_adress_b,
    :additional_contact_email_b,
    :additional_contact_phone_b,
    :additional_contact_single,
    :foto_permission,
    :pronoun,
    :passport_germany,
    :passport_nationality,
    :passport_approved,
    :languages_spoken,
    :shirt_size,
    :uniform_size,
    :can_swim,
    :diet,
    :medical_eating_disorders
  ]

  # The payment choice and the account, which the form offers only while the
  # person is registered (contactable/_finance_fields); afterwards they are
  # part of the contract and only finance changes them. status, sepa_status
  # and wsj_role are not taken here at all: the status page
  # (Person::StatusController) and the finance actions change them, with
  # their own permissions.
  WSJRDP_REGISTERED_PERMITTED_ATTRS = [
    :early_payer,
    :sepa_name,
    :sepa_address,
    :sepa_mail,
    :sepa_iban,
    :sepa_bic
  ].freeze

  def permitted_attrs
    attrs = super.dup
    attrs += WSJRDP_ALWAYS_PERMITTED_ATTRS
    attrs += WSJRDP_REGISTERED_PERMITTED_ATTRS if entry.status == "registered" || can?(:update_finance, entry)
    attrs += [:sepa_mandate_id] if can?(:update_finance, entry)
    attrs += [:wsjrdp_email] if can?(:update_wsjrdp_email, entry)
    attrs += [:moss_email] if can?(:update_moss_email, entry)
    attrs
  end

  # Override crud_controller
  # Display a form to edit an exisiting entry of this model.
  #   GET /entries/1/edit
  def edit(&block)
    @rdp_groups = YAML.load_file(HitobitoWsjrdp2027::Wagon.root.join("config/rdp_groups.yml"))[Rails.env]

    respond_with(entry, &block)
  end
end
