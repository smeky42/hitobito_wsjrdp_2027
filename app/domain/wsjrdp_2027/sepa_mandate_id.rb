# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027
  # The person a SEPA mandate reference belongs to, read as wsjrdp_scripts
  # reads it from bank statements (hitobito_id_from_sepa_mandate_id):
  # "wsjrdp2027", an optional "-", the person's id; anything after the id must
  # not start with a digit.
  module SepaMandateId
    PATTERN = /\Awsjrdp2027-?(\d+)/

    # The characters SEPA allows in a mandate reference, at most 35.
    FORMAT = %r{\A[A-Za-z0-9+?/\-:().,' ]{1,35}\z}

    module_function

    def person_id(mandate_id)
      match = PATTERN.match(mandate_id.to_s.strip.downcase)
      match && Integer(match[1], 10)
    end

    def valid_for?(mandate_id, person_id)
      FORMAT.match?(mandate_id.to_s) && person_id(mandate_id) == person_id
    end
  end
end
