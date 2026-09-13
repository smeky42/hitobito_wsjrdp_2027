# frozen_string_literal: true

#  Copyright (c) 2025 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Reading a boolean out of a request. Deliberately strict in both
# directions: a value has to spell out which of the two it means, and
# anything else -- a typo, an empty string, a missing key -- is neither.
# That is what lets a caller tell "said no" apart from "said nothing".
module Fin::AccessHelper
  private

  def param_is_true(params, key)
    if params.nil?
      false
    else
      val = params[key].to_s.downcase
      ["true", "t", "y", "yes", "1"].any?(val)
    end
  end

  def param_is_false(params, key)
    if params.nil?
      false
    else
      val = params[key].to_s.downcase
      ["false", "f", "n", "no", "0", "nil", "none"].any?(val)
    end
  end
end
