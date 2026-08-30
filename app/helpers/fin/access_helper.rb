# frozen_string_literal: true

#  Copyright (c) 2025 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Fin::AccessHelper
  extend ActiveSupport::Concern

  included do
    ##
    # For testing and to imitate output without accounting rights,
    # accounting rights can be disabled using the can_fin query
    # parameter. Important: It is not possible to gain accounting
    # rights this way.
    def get_can_fin(entry, params: nil, cookies: nil)
      can?(:log, entry) && !param_is_false(params, :can_fin)
    end

    def get_can_fin_admin(subject, params: nil, cookies: nil)
      can?(:fin_admin, subject) && (param_is_true(params, :fin_admin) || param_is_true(cookies, :fin_admin))
    end
  end

  private

  def check_fin_params_and_cookies
    if param_is_true(params, :fin_admin)
      cookies[:fin_admin] = true
    elsif param_is_false(params, :fin_admin)
      cookies[:fin_admin] = false
    end
    Rails.logger.debug { "cookies[:fin_admin]: #{cookies[:fin_admin].inspect}" }

    if param_is_true(params, :can_fin)
      cookies[:can_fin] = true
    elsif param_is_false(params, :can_fin)
      cookies[:can_fin] = false
    end
    Rails.logger.debug { "cookies[:can_fin]: #{cookies[:can_fin].inspect}" }
  end

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
