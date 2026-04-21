# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class MoveDataFromFeeRules < ActiveRecord::Migration[7.1]
  def change
    reversible do |direction|
      direction.up do
        execute <<-SQL
UPDATE people AS p
SET wsjrdp_total_fee_reduction = f.total_fee_reduction_cents::numeric / 100::numeric,
wsjrdp_total_fee_reduction_hint = f.total_fee_reduction_comment
FROM wsj27_rdp_fee_rules as f
WHERE p.id = f.people_id AND f.status = 'active' AND f.total_fee_reduction_cents IS NOT NULL AND f.total_fee_reduction_cents <> 0
        SQL
      end
    end
  end
end
