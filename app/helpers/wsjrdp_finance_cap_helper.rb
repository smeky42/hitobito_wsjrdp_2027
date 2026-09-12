# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# What the session bar (layouts/_wsjrdp_session_bar, doc/roles.md -> "The
# finance cap") needs: the tier the roles grant, the tier in force, which
# tiers may be chosen, and whether the bar shows at all.
module WsjrdpFinanceCapHelper
  # The tiers before and after the cap, as {by_roles:, effective:} -- nil
  # only for an ability that carries no user context at all, e.g. a service
  # token's. Holding no finance permission is a tier of its own
  # (:finance_none), not a missing answer.
  def finance_tiers
    context = current_ability.respond_to?(:user_context) ? current_ability.user_context : nil
    return nil unless context.respond_to?(:finance_tier_by_roles)

    {by_roles: context.finance_tier_by_roles, effective: context.finance_tier}
  end

  # Does the cap actually lower the tier? No cap, or a cap at or above the
  # roles' tier: no.
  def finance_tier_reduced?
    tiers = finance_tiers
    tiers.present? && tiers[:by_roles] != tiers[:effective]
  end

  # The tiers the bar offers, in rank order: up to the roles' own -- anything
  # above it could not be granted anyway.
  def selectable_finance_tiers
    tiers = finance_tiers
    return [] if tiers.nil?

    all = Wsjrdp2027::FinanceCap::TIERS
    all.take(all.index(tiers[:by_roles]) + 1)
  end

  # Whether the yellow bar shows, by the session's mode (finance_tier_bar):
  # always; never; or, on demand (the default), while the cap lowers the tier
  # or a cap is set at all.
  def finance_tier_bar?
    case finance_tier_bar
    when :always then true
    when :hidden then false
    else finance_tier_reduced? || max_finance_permission.present?
    end
  end

  # The German name of a tier, from its permission.
  def finance_tier_label(permission)
    t("wsjrdp.finance_tiers.#{permission}")
  end
end
