# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# What happened to a WsjrdpDeregistration, written once and never changed:
# create (a new row), update (any change, the status included) or notify (a
# form or a confirmation sent). action says what for, e.g. form_created or
# revoked; from_status and to_status are set where the status changed,
# field_changes holds the changed values as {"attribute" => [before, after]}.
# Who did it, created it and changed it last comes from these events.
class WsjrdpDeregistrationEvent < ActiveRecord::Base
  EVENTS = %w[create update notify].freeze

  validates :event, inclusion: {in: EVENTS}
end
