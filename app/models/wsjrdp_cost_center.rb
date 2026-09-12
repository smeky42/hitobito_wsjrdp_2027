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
  # The totals are the Konto perspective (signed_base_amount), the same
  # net cash-flow of the tagged bookings the page has always shown, and they
  # follow the PRIMARY cost center only (`cost_center_number`), never the
  # secondary one.
  scope :with_booking_summary, -> {
    totals = DatevBooking.where.not(cost_center_number: nil)
      .select("cost_center_number, SUM(signed_base_amount) AS booking_sum, " \
              "COUNT(*) AS booking_count")
      .group(:cost_center_number)
    from(Arel.sql(<<~SQL.squish))
      (SELECT cc.*,
              COALESCE(t.booking_sum, 0) AS booking_sum,
              COALESCE(t.booking_count, 0) AS booking_count
         FROM wsjrdp_cost_centers cc
         LEFT JOIN (#{totals.to_sql}) t ON t.cost_center_number = cc.number)
      AS wsjrdp_cost_centers
    SQL
  }

  def active?
    moss_status == STATUS_ACTIVE
  end

  def to_s
    "#{number} #{display_short_name}"
  end
end
