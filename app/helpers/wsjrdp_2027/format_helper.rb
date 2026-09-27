# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The core's attribute list labels each attribute once per model; the token
# column of a service token is labelled by what it holds: "Token-Hash" for a
# hash, "Token" for a token stored as it is (WsjrdpServiceTokenHelper).
module Wsjrdp2027::FormatHelper
  def labeled_attr(obj, attr, display_link: true)
    return super unless attr.to_sym == :token && obj.is_a?(::ServiceToken)

    labeled(service_token_token_label(obj), format_attr(obj, attr, display_link: display_link))
  end
end
