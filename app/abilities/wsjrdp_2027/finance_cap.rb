# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# A per-session CAP on the finance tier a person exercises -- so someone who
# holds :finance_manage can work as if they held only :finance_read, and see
# the pages the way a reader sees them.
#
# The cap names the highest finance tier that stays in effect; every tier
# above it is taken OUT of the person's permission set before the Ability is
# built (Wsjrdp2027::UserContext). Capping at the lowest tier, :finance_none,
# therefore leaves no finance rights at all. Nothing else changes -- the cap only ever
# subtracts, so it can never grant a tier the person's roles do not hold, and
# it touches no permission outside the finance tiers. A stale or unknown value
# counts as no cap.
#
# Where it comes from: session[:max_finance_permission], set through the
# ?max_finance_permission=<tier> query parameter (Wsjrdp2027::Concerns::
# SessionSettings) and read in ApplicationController#current_ability. The
# handover into AbilityDsl::UserContext -- whose constructor the core calls
# with the user alone -- is a thread-local that lives exactly as long as the
# Ability's own constructor (.with), so an Ability built anywhere else
# (jobs, TableDisplay, another person's ability) is never capped by accident.
module Wsjrdp2027::FinanceCap
  # Ascending, i.e. index == rank. The lowest is the pseudo tier
  # :finance_none, which nobody holds as a permission -- it is what holding
  # none of them is called, and capping at it takes every finance tier away.
  TIERS = [:finance_none, *Wsjrdp2027::FinanceAccess::FINANCE_TIERS].freeze

  KEY = :wsjrdp_2027_max_finance_permission

  module_function

  def valid?(value)
    TIERS.include?(value.to_s.to_sym)
  end

  # The highest tier in a permission set, :finance_none without any.
  def highest(permissions)
    (TIERS & permissions).last || :finance_none
  end

  # The tiers a cap removes: everything ranked above it.
  def removed_by(cap)
    return [].freeze if cap.nil?

    TIERS.drop(TIERS.index(cap.to_sym) + 1).freeze
  end

  def with(cap)
    previous = Thread.current[KEY]
    Thread.current[KEY] = cap
    yield
  ensure
    Thread.current[KEY] = previous
  end

  def current
    Thread.current[KEY]
  end
end
