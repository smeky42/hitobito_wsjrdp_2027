# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The Buchungsstapel (booking batches) dataset for the generic CNF filter
# (doc/wsjrdp/generic_filter_builder.md): attribute declarations and the
# request-time binding, one consumer of the filter-schema protocol next to
# Fin::DatevBookingsFilterSchema, Fin::LedgerAccountsFilterSchema,
# Fin::CostCentersFilterSchema and Fin::PersonalAccountsFilterSchema.
#
# The base relation left-joins bookings and groups by batch id, so
# `booking_count` is an ordinary column the compiler can filter on -- the page
# never filters an Array in Ruby.
module Fin::BookingBatchesFilterSchema
  extend Wsjrdp::Filtering::FilterSchema

  # All case variants of the text operators, the same list the other pages
  # offer (Fin::DatevBookingsFilterSchema::TEXT_OPERATORS), glob pair included.
  TEXT_OPERATORS = Fin::DatevBookingsFilterSchema::TEXT_OPERATORS

  # The distinct periods (months) that occur in the data, derived from
  # period_to and formatted as YYYY-MM. Read when the catalog is rendered, so
  # a newly imported batch appears without a code change.
  PERIOD_OPTIONS = Wsjrdp::Filtering::Options.values(-> {
    DatevBookingBatch.distinct.order(period_to: :desc).pluck(:period_to)
      .map { |d| [d.strftime("%Y-%m"), d.strftime("%Y-%m")] }.uniq
  })

  SCHEMA = Wsjrdp::Filtering::Schema.define do |s|
    s.attribute key: :label, short_key: :q, label: "Bezeichnung",
      type: Wsjrdp::Filtering::Types::TEXT, operators: TEXT_OPERATORS,
      column: :label
    s.attribute key: :period, short_key: :p, label: "Periode",
      type: Wsjrdp::Filtering::Types::ENUM, operators: %i[in not_in],
      column: ->(t) {
        Arel::Nodes::NamedFunction.new("TO_CHAR",
          [t[:period_to], Arel::Nodes.build_quoted("YYYY-MM")])
      },
      options: PERIOD_OPTIONS
  end

  def self.bound(except: nil)
    SCHEMA.bind(
      DatevBookingBatch
        .left_joins(:bookings)
        .select("datev_booking_batches.*, COUNT(datev_bookings.id) AS booking_count")
        .group("datev_booking_batches.id"),
      except: except
    )
  end
end
