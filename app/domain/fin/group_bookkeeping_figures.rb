# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027
#
# The three figures above a group's Buchungen table: what its bookings add up
# to, how much of that counts against the unit's budget, and what share of the
# budget that is.
#
# They are read over the group's PINNED set -- every booking whose primary or
# secondary cost center is one of the group's -- and therefore NOT over what the
# user's filter leaves. That is the point of the tiles: the table below them
# answers "what am I looking at", the tiles answer "where does the unit stand",
# and a filter must not move the second question's answer. The summary line of
# the table states the filtered figures beside them
# (Fin::BookingsHelper#booking_table_summary).
#
# The pinned set is built here as `where(cost_center_number: …).or(… secondary …)`
# -- the same two-column set Group::BookingsController#group_bookings scopes its
# lookup to, and the same one the table's fixed `any_cost_center` slot compiles.
# Compiling that slot instead would need the table's resolved state, which is
# exactly the thing these figures must not depend on.
#
# No formatting and no I18n live here: the booking sums go out signed (expenses
# negative, doc/fin/money_conventions.md), the budget positive as it is stored,
# and the page decides how they look. Every figure is ONE aggregate query,
# memoized per instance.
class Fin::GroupBookkeepingFigures
  def initialize(cost_center_numbers)
    @numbers = Array(cost_center_numbers).compact_blank
  end

  # What the group's bookings add up to, from the Konto perspective.
  def total
    @total ||= pinned_bookings.sum(:signed_base_amount)
  end

  # The part of that sum which counts against the unit's budget, over the one
  # SQL definition of the rule every other reader uses (doc/fin/unit_budget.md).
  def unit_budget
    @unit_budget ||=
      pinned_bookings.where(DatevBooking::EFFECTIVE_IS_UNIT_BUDGET_SQL)
        .sum(:signed_base_amount)
  end

  # The budget those bookings are measured against: the Gesamtbudget of the
  # group's own cost centers -- the ones marked `is_unit_cost_center`. A cost
  # center of the group that is NOT a unit's own carries the contingent's money
  # and says nothing about what the unit may spend, so it stays out. 0 where no
  # such cost center (or no budget on one) exists. Budgets are expense budgets
  # and stored positive (doc/fin/unit_budget.md).
  def budget
    @budget ||= WsjrdpCostCenter.where(number: @numbers, is_unit_cost_center: true)
      .sum(:effective_total_budget)
  end

  # Whether there is a budget to measure against at all.
  def budget? = budget.present? && !budget.zero?

  # How much of the budget is used, in percent: nil where there is no budget to
  # measure against, so the page can say so instead of printing a figure it
  # cannot compute. The budget is positive, the booking sum is signed with
  # expenses negative, so the share is taken over the EXPENSES and comes out
  # positive for a spending unit.
  def used_share
    return nil unless budget?

    expenses_unit_budget * 100 / budget
  end

  # The two booking sums as EXPENSES, i.e. with their sign turned: the signed
  # figures above follow the money conventions (expenses negative), the tiles
  # of the group's page talk of what was spent as positive amounts -- like the
  # budget, which needs no turning.
  def expenses_total = -total

  def expenses_unit_budget = -unit_budget

  private

  # Every booking of the group, on either cost-center column, carrying the
  # Unit-Budget joins the expression above names. One relation, so both sides of
  # the `or` are structurally identical.
  def pinned_bookings
    scope = DatevBooking.with_unit_budget
    scope.where(cost_center_number: @numbers)
      .or(scope.where(secondary_cost_center_number: @numbers))
  end
end
