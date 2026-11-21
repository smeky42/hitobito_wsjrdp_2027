# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# For the specs of the credential store that boot Rails: a registry with
# one kind changed.
module CredentialsSpecHelpers
  # The registry with the kind changed by the block, which gets its fields
  # and the kind itself.
  def changed_kinds(kind)
    data = YAML.safe_load_file(Wsjrdp::Credentials::Kinds::PATH)
    yield data["kinds"][kind]["fields"], data["kinds"][kind]
    Wsjrdp::Credentials::Kinds.new(data)
  end
end

RSpec.configure { |config| config.include CredentialsSpecHelpers }
