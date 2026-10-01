# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class WsjrdpCostCenter < ActiveRecord::Base
  include WsjrdpBudgetable

  STATUS_ACTIVE = "active"
  STATUS_DEACTIVATED = "deactivated"

  # The foreign key is spelled out: the column is `manager_person_id`, not the
  # `manager_id` a belongs_to would derive from the association name.
  belongs_to :manager, class_name: "Person", optional: true,
    foreign_key: :manager_person_id, inverse_of: :managed_cost_centers

  validates :number, presence: true, uniqueness: true

  # The sub cost centers below this cost center, linked by its number (there is
  # no FK).
  # rubocop:disable Rails/HasManyOrHasOneDependent -- deliberately no
  # :dependent option: deleting a cost center leaves its sub cost centers
  # alone. They keep their `cost_center_number`, so nothing is destroyed behind
  # the user's back and the link heals if the cost center returns (cost centers
  # are master data synced from DATEV and Moss).
  has_many :sub_cost_centers, -> { order(:number) },
    class_name: "WsjrdpSubCostCenter", primary_key: :number,
    foreign_key: :cost_center_number, inverse_of: :cost_center
  # rubocop:enable Rails/HasManyOrHasOneDependent

  # moss_status is NULL for cost centers unknown to Moss
  scope :active, -> { where(moss_status: STATUS_ACTIVE) }
  scope :deactivated, -> { where(moss_status: [STATUS_DEACTIVATED, nil]) }

  # Every cost center with its booking totals as REAL columns:
  #
  #   booking_sum    SUM of signed_base_amount over the bookings tagged with
  #                  this cost center, 0 when it has none
  #   booking_count  how many bookings carry the cost center, 0 when none
  #
  # Both are computed in ONE derived table aliased back to
  # `wsjrdp_cost_centers`, so they are ordinary columns of the relation: the
  # Kostenstellen page's filter compiles conditions against them
  # (Fin::CostCentersFilterSchema), the table sorts by them, and
  # `.sum(:booking_sum)` / `.sum(:booking_count)` give the footer totals of the
  # FILTERED set. A LEFT JOIN, so a cost center without bookings still appears.
  #
  # The totals are the Konto perspective (signed_base_amount), the same net
  # cash-flow of the tagged bookings the page has always shown. `view` names the
  # cost center a booking counts for (VIEWS):
  #
  #   primary    its cost_center_number
  #   secondary  its secondary_cost_center_number (a booking without one counts
  #              nowhere)
  #   any        either of the two -- a booking counts ONCE per cost center, but
  #              for both when the two differ, so a sum over several rows counts
  #              it twice
  #   budget     its budget assignment (DatevBooking::BUDGET_COST_CENTER_SQL)
  VIEWS = %w[primary secondary any budget].freeze

  scope :with_booking_summary, ->(view = "primary") {
    from(Arel.sql(<<~SQL.squish))
      (SELECT cc.*,
              COALESCE(t.booking_sum, 0) AS booking_sum,
              COALESCE(t.booking_count, 0) AS booking_count
         FROM wsjrdp_cost_centers cc
         LEFT JOIN (#{booking_totals_sql(view)}) t ON t.cost_center_number = cc.number)
      AS wsjrdp_cost_centers
    SQL
  }

  # The bookings of one cost center under `view` (VIEWS), as a DatevBooking
  # relation that carries the Unit-Budget joins.
  def self.bookings_for(number, view)
    scope = DatevBooking.with_unit_budget_accounts
    case view.to_s
    when "secondary" then scope.where(secondary_cost_center_number: number)
    when "any" then scope.where(cost_center_number: number).or(scope.where(secondary_cost_center_number: number))
    when "budget"
      scope.where(Arel::Nodes::Equality.new(Arel.sql("(#{DatevBooking::BUDGET_COST_CENTER_SQL})"),
        Arel::Nodes.build_quoted(number)))
    else scope.where(cost_center_number: number)
    end
  end

  # {cost_center_number, booking_sum, booking_count} per cost center under `view`.
  def self.booking_totals_sql(view)
    columns = "SUM(signed_base_amount) AS booking_sum, COUNT(*) AS booking_count"
    case view.to_s
    when "secondary"
      DatevBooking.where.not(secondary_cost_center_number: [nil, ""])
        .select("secondary_cost_center_number AS cost_center_number, #{columns}")
        .group(:secondary_cost_center_number).to_sql
    when "any"
      legs = DatevBooking.where.not(cost_center_number: nil)
        .select(:cost_center_number, :signed_base_amount).to_sql
      second = DatevBooking.where.not(secondary_cost_center_number: [nil, ""])
        .where("secondary_cost_center_number IS DISTINCT FROM cost_center_number")
        .select("secondary_cost_center_number AS cost_center_number", :signed_base_amount).to_sql
      "SELECT cost_center_number, #{columns} FROM (#{legs} UNION ALL #{second}) legs GROUP BY cost_center_number"
    when "budget"
      assigned = "(#{DatevBooking::BUDGET_COST_CENTER_SQL})"
      DatevBooking.with_unit_budget_accounts
        .select("#{assigned} AS cost_center_number, SUM(datev_bookings.signed_base_amount) AS booking_sum, COUNT(*) AS booking_count")
        .group(Arel.sql(assigned)).to_sql
    else
      DatevBooking.where.not(cost_center_number: nil)
        .select("cost_center_number, #{columns}").group(:cost_center_number).to_sql
    end
  end

  def active?
    moss_status == STATUS_ACTIVE
  end

  def to_s
    "#{number} #{display_short_name}"
  end
end
