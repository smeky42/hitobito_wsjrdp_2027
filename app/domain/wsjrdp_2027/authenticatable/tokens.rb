# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027
  module Authenticatable
    # A service token is found by the digest of the key the request carries
    # (Wsjrdp2027::ServiceToken); a request that carries the stored digest
    # itself finds nothing.
    module Tokens
      def service_token
        @service_token ||= extract_request_token(:token) do |token|
          ::ServiceToken.find_by_plain_token(token)
        end
      end
    end
  end
end
