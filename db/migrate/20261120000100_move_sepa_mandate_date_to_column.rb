# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Moves the signature date of the SEPA mandate from either
# people.additional_info->>'sepa_mandate_date' (an ISO string) or
# people.print_at into a column of its own.
class MoveSepaMandateDateToColumn < ActiveRecord::Migration[7.1]
  ISO_DATE = "^[0-9]{4}-[0-9]{2}-[0-9]{2}$"

  def change
    add_column :people, :sepa_mandate_date, :date, null: true, comment: "date of the SEPA mandate"

    reversible do |dir|
      dir.up { move_into_column }
      # Runs before the column is removed (change reverses its order).
      dir.down { move_into_additional_info }
    end
  end

  private

  def move_into_column
    execute <<~SQL
      UPDATE people
      SET sepa_mandate_date = COALESCE(
        CASE WHEN additional_info->>'sepa_mandate_date' ~ '#{ISO_DATE}'
             THEN (additional_info->>'sepa_mandate_date')::date END,
        print_at)
      WHERE (additional_info ? 'sepa_mandate_date') OR print_at IS NOT NULL;
    SQL

    execute <<~SQL
      UPDATE people
      SET additional_info = additional_info - 'sepa_mandate_date'
      WHERE additional_info ? 'sepa_mandate_date';
    SQL
  end

  def move_into_additional_info
    execute <<~SQL
      UPDATE people
      SET additional_info = jsonb_set(COALESCE(additional_info, '{}'::jsonb), '{sepa_mandate_date}',
        to_jsonb(to_char(sepa_mandate_date, 'YYYY-MM-DD')))
      WHERE sepa_mandate_date IS NOT NULL;
    SQL
  end
end
