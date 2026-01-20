# frozen_string_literal: true

#  Copyright (c) 2025 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027::GroupsController
  def permitted_attrs
    attrs = super
    if can?(:log, entry)
      attrs += [:unit_code, :support_cmt_mail_addresses, :support_cmt_mail_addresses_string]
    end
    attrs -= [:text_message_username, :text_message_password, :text_message_provider, :text_message_originator]
    attrs
  end
end
