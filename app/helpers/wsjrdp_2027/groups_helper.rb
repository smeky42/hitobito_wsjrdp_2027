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

  def format_group_support_cmt_mail_addresses(group)
    bcc = group.support_cmt_mail_addresses
    bcc.map { |e| auto_link(e) }.join("<br/>\n").html_safe if bcc.present?
  end
end
