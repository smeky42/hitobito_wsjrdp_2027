# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027
  YearMonthCents = Data.define(:year_month, :cents) do
    def initialize(year_month:, cents:)
      if !year_month.is_a?(YearMonth)
        year_month = YearMonth.new(year_month[0], year_month[1])
      end
      super
    end

    def [](index)
      case index
      when :year_month, "year_month", 0, -2
        year_month
      when :cents, "cents", 1, -1
        cents
      when :eur, "eur"
        eur
      end
    end

    def eur
      (cents.to_f / 100)
    end

    def eur_s
      eur.to_s.sub(/[.]0$/, "")
    end

    delegate :year, :month, :year_month_i, :distance_in_months_to, to: :year_month
  end
end
