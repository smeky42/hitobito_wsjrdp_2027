# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Which finance tier a person exercises in one session -- so someone who holds
# :finance_manage can work as if they held only :finance_read and see the
# pages the way a reader sees them, and so that the manage tier is not in
# force unless it was asked for.
#
# Three tiers tell the whole story (doc/roles.md -> "The finance cap"):
#
#   by roles   the ceiling, from the person's role permissions
#   default    what applies unasked: the highest tier up to the ceiling that
#              is not an ELEVATED_TIER
#   effective  the session's pick, never above the ceiling; the default when
#              there is no pick
#
# Everything above the effective tier is taken OUT of the permission set
# before the Ability is built (Wsjrdp2027::UserContext), so the cap only ever
# subtracts. A pick can raise from the default back up to the ceiling, but it
# can never grant a tier the roles do not hold, which is what makes a
# client-chosen value safe to honour.
#
# The resolution happens in Wsjrdp2027::Ability, BEFORE the user context is
# built, and only when that constructor was given the keyword at all. An
# Ability built without it (a job, TableDisplay, an API request, another
# person's rights) passes UNSET and is left completely alone -- it keeps every
# tier its roles grant. The handover into AbilityDsl::UserContext, whose
# constructor the core calls with the user alone, is a thread-local that lives
# exactly as long as the Ability's own constructor (.with).
module Wsjrdp2027::FinanceCap
  # Ascending, i.e. index == rank. The lowest is the pseudo tier
  # :finance_none, which nobody holds as a permission -- it is what holding
  # none of them is called, and capping at it takes every finance tier away.
  NONE = :finance_none
  TIERS = [NONE, *Wsjrdp2027::FinanceAccess::FINANCE_TIERS].freeze

  # Tiers nobody exercises unasked. A role may grant them, but they only take
  # effect once the person picks them for the session; without a pick the
  # highest tier below applies. Managing the finance data is powerful enough
  # to be worth that one deliberate step.
  ELEVATED = %i[finance_manage].freeze

  # Told apart from "no pick": no keyword at all means no resolution at all.
  UNSET = :unset

  KEY = :wsjrdp_2027_max_finance_permission

  module_function

  def valid?(value)
    TIERS.include?(value.to_s.to_sym)
  end

  def elevated?(tier)
    ELEVATED.include?(tier)
  end

  # The highest tier in a permission set, :finance_none without any.
  def highest(permissions)
    (TIERS & permissions).last || NONE
  end

  # The ceiling of a person, straight from their roles. Read WITHOUT building
  # an ability, so the session can ask before one exists. It matches what the
  # user context derives: the core expands Role::PermissionImplications, and
  # no finance tier appears in that table (spec/abilities/finance_cap_spec).
  def granted_for(person)
    return NONE if person.nil?

    highest(person.roles.collect(&:permissions).flatten.uniq)
  end

  # What applies unasked: the highest tier up to the ceiling that nobody has
  # to ask for.
  def default_for(granted)
    index = TIERS.index(granted.to_sym)
    TIERS.first(index + 1).reverse.find { |tier| !elevated?(tier) } || NONE
  end

  # The tier in force: the pick, never above the ceiling, the default without
  # one. nil for UNSET, which means "do not touch this ability at all".
  def resolve(person, pick)
    return nil if pick == UNSET

    granted = granted_for(person)
    picked = valid?(pick) ? pick.to_sym : nil
    return default_for(granted) if picked.nil?

    lower_of(picked, granted)
  end

  # Does a pick ask for more than the roles grant? The session drops such a
  # value instead of carrying it along uselessly.
  def exceeds?(pick, person)
    return false unless valid?(pick)

    TIERS.index(pick.to_sym) > TIERS.index(granted_for(person))
  end

  def lower_of(one, other)
    TIERS[[TIERS.index(one.to_sym), TIERS.index(other.to_sym)].min]
  end

  # The tiers a tier in force removes: everything ranked above it.
  def removed_by(tier)
    return [].freeze if tier.nil?

    TIERS.drop(TIERS.index(tier.to_sym) + 1).freeze
  end

  def with(tier)
    previous = Thread.current[KEY]
    Thread.current[KEY] = tier
    yield
  ensure
    Thread.current[KEY] = previous
  end

  def current
    Thread.current[KEY]
  end
end
