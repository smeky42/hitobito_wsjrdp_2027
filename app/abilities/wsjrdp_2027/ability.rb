# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Prepended to ::Ability: resolves the session's finance tier and hands the
# result to the UserContext the core builds inside its constructor
# (Wsjrdp2027::FinanceCap).
#
#   Ability.new(person)                                    # untouched
#   Ability.new(person, max_finance_permission: nil)       # the default tier
#   Ability.new(person, max_finance_permission: :finance)  # that tier
#
# Resolving HERE, before the context exists, is what keeps the context simple:
# the tier that ends up in the thread-local is the one in force, so the
# context only has to subtract what lies above it. Without the keyword the
# resolution is skipped entirely -- that is the line between a session and
# everything else (jobs, API requests, abilities for other people).
module Wsjrdp2027::Ability
  def initialize(user, max_finance_permission: Wsjrdp2027::FinanceCap::UNSET)
    tier = Wsjrdp2027::FinanceCap.resolve(user, max_finance_permission)
    Wsjrdp2027::FinanceCap.with(tier) { super(user) }
  end

  # The core keys caches on this; an ability at another tier must not share
  # them with one of the same person at a different tier.
  def identifier
    tier = user_context&.finance_tier_in_force
    tier ? "#{super}-fin-#{tier}" : super
  end
end
