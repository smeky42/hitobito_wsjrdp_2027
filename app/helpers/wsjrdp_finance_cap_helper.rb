# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# What the session bar (layouts/_wsjrdp_session_bar, doc/roles.md -> "The
# finance cap") needs: the three tiers, which of them may be picked, which
# way the current one departs from the default, and whether the bar shows.
module WsjrdpFinanceCapHelper
  # The three tiers as {by_roles:, default:, effective:} -- nil only for an
  # ability that carries no user context at all, e.g. a service token's.
  # Holding no finance permission is a tier of its own (:finance_none), not a
  # missing answer.
  def finance_tiers
    context = current_ability.respond_to?(:user_context) ? current_ability.user_context : nil
    return nil unless context.respond_to?(:finance_tier_by_roles)

    {by_roles: context.finance_tier_by_roles,
     default: context.finance_tier_default,
     effective: context.finance_tier}
  end

  # Which way the tier in force departs from the default: :raised, :lowered,
  # or :same. It names the situation the bar's one action undoes.
  def finance_tier_direction
    tiers = finance_tiers
    return :same if tiers.nil?

    all = Wsjrdp2027::FinanceCap::TIERS
    case all.index(tiers[:effective]) <=> all.index(tiers[:default])
    when 1 then :raised
    when -1 then :lowered
    else :same
    end
  end

  # Does the tier in force depart from the default at all?
  def finance_tier_deviates?
    finance_tier_direction != :same
  end

  # Is the tier in force one that had to be asked for? Those are shown
  # whatever the bar's mode says -- rights one had to reach for should not be
  # in force invisibly.
  def finance_tier_elevated?
    tiers = finance_tiers
    tiers.present? && Wsjrdp2027::FinanceCap.elevated?(tiers[:effective])
  end

  # The tiers the bar offers, in rank order: from none up to the roles' own --
  # anything above it could not be granted anyway.
  def selectable_finance_tiers
    tiers = finance_tiers
    return [] if tiers.nil?

    all = Wsjrdp2027::FinanceCap::TIERS
    all.take(all.index(tiers[:by_roles]) + 1)
  end

  # Whether the bar shows. An elevated tier always shows it, whatever the
  # mode. Otherwise by the session's mode (finance_tier_bar): always; never;
  # or, on demand (the default), while the tier departs from the default or a
  # tier was picked at all.
  def finance_tier_bar?
    return true if finance_tier_elevated?

    case finance_tier_bar
    when :always then true
    when :hidden then false
    else finance_tier_deviates? || max_finance_permission.present?
    end
  end

  # The German name of a tier, from its permission.
  def finance_tier_label(permission)
    t("wsjrdp.finance_tiers.#{permission}")
  end
end
