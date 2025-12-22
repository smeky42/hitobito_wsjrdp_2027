# frozen_string_literal: true

#  Copyright (c) 2025 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module WsjrdpFinHelper
  extend ActiveSupport::Concern

  included do
    ##
    # For testing and to imitate output without accounting rights,
    # accounting rights can be disabled using the can_fin query
    # parameter. Important: It is not possible to gain accounting
    # rights this way.
    def get_can_fin(person, params: nil)
      can?(:log, person) && !param_is_false(params, :can_fin)
    end

    def get_can_fin_admin(person, params: nil)
      can?(:log, person) && [1, 2, 65, 1309].any?(current_user.id) && param_is_true(params, :fin_admin)
    end
  end

  private

  def param_is_true(params, key)
    if params.nil?
      false
    else
      val = (params[key] || "").downcase
      ["true", "t", "y", "yes", "1"].any?(val)
    end
  end

  def param_is_false(params, key)
    if params.nil?
      false
    else
      val = (params[key] || "").downcase
      ["false", "f", "n", "no", "0", "nil", "none"].any?(val)
    end
  end
end
