# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027
  YearMonthEur = Data.define(:year_month, :eur) do
    alias_method :to_ary, :deconstruct

    def initialize(year_month:, eur:)
      if !year_month.is_a?(YearMonth)
        year_month = YearMonth.new(year_month[0], year_month[1])
      end
      super
    end

    def [](index)
      case index
      when :year_month, "year_month", 0, -2
        year_month
      when :eur, "eur", 1, -1
        decimal
      when :cents, "cents"
        cents
      end
    end

    def first = year_month

    def last = eur

    def cents
      (eur * BigDecimal(100)).to_i
    end

    def to_year_month_cents
      YearMonthCents.new(year_month, cents)
    end

    delegate :year, :month, :year_month_i, :distance_in_months_to, :to_time_with_zone, to: :year_month
  end
end
