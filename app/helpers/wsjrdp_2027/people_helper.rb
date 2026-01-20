# frozen_string_literal: true

#  Copyright (c) 2025 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027::PeopleHelper
  include ContractHelper

  def format_person_unit_code(person)
    make_unit_code_display(person.unit_code, not_set_text: "Nicht gesetzt", search_link: true)
  end

  def format_person_cluster_code(person)
    make_unit_code_display(person.cluster_code, not_set_text: "Nicht gesetzt", attribute: :cluster_code, search_link: true)
  end

  def format_person_status(person)
    status_de = Settings.status[person.status]
    status_de.blank? ? person.status : "#{person.status} (#{status_de})"
  end

  def format_person_deregistration_issue(person)
    auto_link_escaped_multiline(person.deregistration_issue) if person.deregistration_issue.present?
  end

  def format_person_missing_installment_issue(person)
    auto_link_escaped_multiline(person.missing_installment_issue) if person.missing_installment_issue.present?
  end
end
