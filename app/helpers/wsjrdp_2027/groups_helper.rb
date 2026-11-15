# frozen_string_literal: true

#  Copyright (c) 2025 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027::GroupsHelper
  include ContractHelper

  def format_group_unit_code(group)
    make_unit_code_display(group.unit_code, not_set_text: "Nicht gesetzt")
  end

  # The stored value, or the rule muted where the unit has none.
  def format_group_initial_unit_size(group)
    format_group_count_or_rule(group.initial_unit_size, Group::DEFAULT_INITIAL_UNIT_SIZE)
  end

  def format_group_expected_unit_size(group)
    format_group_count_or_rule(group.expected_unit_size, Group::DEFAULT_EXPECTED_UNIT_SIZE)
  end

  def format_group_expected_ul_number(group)
    format_group_count_or_rule(group.expected_ul_number, Group::DEFAULT_EXPECTED_UL_NUMBER)
  end

  def format_group_expected_patrol_number(group)
    format_group_count_or_rule(group.expected_patrol_number, Group::DEFAULT_EXPECTED_PATROL_NUMBER)
  end

  def format_group_unit_formed_date(group)
    date = group.unit_formed_date
    format_group_count_or_rule(date && l(date), l(Group::DEFAULT_UNIT_FORMED_DATE))
  end

  def format_group_count_or_rule(value, default)
    return value.to_s unless value.nil?

    safe_join([default.to_s, " ", content_tag(:span, "(Regel, nicht gesetzt)", class: "text-muted")])
  end

  def format_group_support_cmt_mail_addresses(group)
    bcc = group.support_cmt_mail_addresses
    bcc.map { |e| auto_link(e) }.join("<br/>\n").html_safe if bcc.present?
  end
end
