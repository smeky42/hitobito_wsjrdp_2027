# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Align the two conversion-rate columns of moss_balance_movements with
# the project-wide FX-rate convention numeric(28, 12) -- see
# doc/fin/money_conventions.md.
class WidenMossBalanceMovementConversionRates < ActiveRecord::Migration[7.1]
  RATE_COLUMNS = [:conversion_rate, :conversion_rate_including_fees].freeze

  def up
    RATE_COLUMNS.each do |column|
      change_column :moss_balance_movements, column, :decimal, precision: 28, scale: 12
    end
  end

  def down
    RATE_COLUMNS.each do |column|
      change_column :moss_balance_movements, column, :decimal, precision: 20, scale: 8
    end
  end
end
