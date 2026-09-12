# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# A sub cost center: a Hitobito-owned refinement of a cost center, below the
# granularity DATEV and Moss know about. It hangs off its cost center by that
# cost center's number, the way the Moss and DATEV tables link to accounts, and
# carries the same names, aliases and budgets. Its number is unique within its
# cost center only.
class WsjrdpSubCostCenter < ActiveRecord::Base
  include WsjrdpBudgetable

  # The keys are spelled out on both sides: the link is by the cost center's
  # `number`, not by its id (`primary_key`), and the column holding it is
  # `cost_center_number`, not the `cost_center_id` a belongs_to would derive
  # from the association name (`foreign_key`).
  #
  # The association is deliberately optional: a sub cost center outlives the
  # cost center it names. `cost_center_number` is NOT NULL and keeps naming
  # that cost center, so the link heals by itself once the cost center is
  # imported again.
  belongs_to :cost_center, class_name: "WsjrdpCostCenter", optional: true,
    foreign_key: :cost_center_number, primary_key: :number,
    inverse_of: :sub_cost_centers

  # The bookings assigned to this sub cost center. The link is by BOTH numbers:
  # `datev_bookings.sub_cost_center_number` names the row and the booking's own
  # `cost_center_number` decides under which cost center that number is read, so
  # a booking of another cost center carrying the same sub cost center number is
  # not listed here. There is no foreign key behind it -- see
  # `DatevBooking#sub_cost_center` for why, and for the stale pairs a DATEV
  # import can leave behind.
  #
  # The price of the instance-dependent scope: the association preloads, but can
  # never be eager-loaded or joined ("The association scope ... is instance
  # dependent"). Use `preload`/`includes`; a join is written out in SQL:
  #   LEFT JOIN wsjrdp_sub_cost_centers scc
  #          ON scc.cost_center_number = datev_bookings.cost_center_number
  #         AND scc.number = datev_bookings.sub_cost_center_number
  #
  # rubocop:disable Rails/HasManyOrHasOneDependent -- deliberately no
  # :dependent option: bookings are independent facts; deleting a sub cost
  # center must never touch them (and there is no FK to nullify).
  has_many :datev_bookings, ->(sub) { where(cost_center_number: sub.cost_center_number) },
    class_name: "DatevBooking", foreign_key: :sub_cost_center_number,
    primary_key: :number, inverse_of: false
  # rubocop:enable Rails/HasManyOrHasOneDependent

  # Mirrors the unique index on [cost_center_number, number]: the same number
  # may be used again under a different cost center.
  validates :number, presence: true, uniqueness: {scope: :cost_center_number}

  # Every sub cost center with its booking totals as REAL columns:
  #
  #   booking_sum    SUM of signed_base_amount over the bookings assigned to
  #                  this sub cost center, 0 when it has none
  #   booking_count  how many bookings are assigned to it, 0 when none
  #
  # Both are computed in ONE derived table aliased back to
  # `wsjrdp_sub_cost_centers`, so they are ordinary columns of the relation:
  # conditions compile against them, a table sorts by them, and
  # `.sum(:booking_sum)` / `.sum(:booking_count)` give the footer totals of the
  # FILTERED set. A LEFT JOIN, so a sub cost center without bookings still
  # appears.
  #
  # The totals follow the PAIR (cost_center_number, sub_cost_center_number), the
  # same link the associations use, so they never bleed across cost centers: a
  # booking of another cost center carrying the same sub cost center number
  # counts towards that other cost center's row only. Bookings without a sub
  # cost center number are not part of any total. The amounts are the Konto
  # perspective (signed_base_amount) and follow the PRIMARY cost center only,
  # never the secondary one.
  scope :with_booking_summary, -> {
    totals = DatevBooking.where.not(sub_cost_center_number: [nil, ""])
      .select("cost_center_number, sub_cost_center_number, " \
              "SUM(signed_base_amount) AS booking_sum, COUNT(*) AS booking_count")
      .group(:cost_center_number, :sub_cost_center_number)
    from(Arel.sql(<<~SQL.squish))
      (SELECT scc.*,
              COALESCE(t.booking_sum, 0) AS booking_sum,
              COALESCE(t.booking_count, 0) AS booking_count
         FROM wsjrdp_sub_cost_centers scc
         LEFT JOIN (#{totals.to_sql}) t
                ON t.cost_center_number = scc.cost_center_number
               AND t.sub_cost_center_number = scc.number)
      AS wsjrdp_sub_cost_centers
    SQL
  }

  def to_s
    "#{number} #{display_short_name}"
  end
end
