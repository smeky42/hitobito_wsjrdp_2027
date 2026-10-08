# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The fee of a person in euros, as columns of people, so that it is always
# consistent with its inputs, whoever changes them (the app or a script with
# SQL), and can be read and summed with plain SQL -- the fee to be paid in
# total against the sum of the fee bookings.
#
#   wsjrdp_regular_full_fee_override  set by finance: the regular full fee of
#                                     this person, whatever the role
#   wsjrdp_extra_total_fee_reduction  set by finance: a second reduction, on
#                                     top of wsjrdp_total_fee_reduction
#   wsjrdp_total_fee_override         set by finance: the total fee of this
#                                     person, whatever the fee and reductions
#
#   wsjrdp_regular_full_fee  generated: the override where set, else the fee of
#                            the payment role before any reduction (the T&R
#                            tariff: YP 3400, UL 2400, IST and BMT 2600, CMT
#                            1600, Extern 0; the same for single payment and
#                            installments). A missing or unknown payment role
#                            gives 0 for a person without a contract or after a
#                            deregistration (registered, deregistration_noted,
#                            deregistered) and an unmistakable placeholder of
#                            10 million otherwise, as the scripts have always
#                            done (wsjrdp2027._people._compute_regular_full_fee_cents).
#   wsjrdp_total_fee         generated: the override where set, else the
#                            regular full fee minus both reductions, not below 0.
#
# A generated column cannot refer to another one (Postgres 16), so the total
# fee repeats the regular full fee's expression.
class AddFeeColumnsToPeople < ActiveRecord::Migration[7.1]
  REGULAR_FULL_FEE_SQL = <<~SQL.squish
    COALESCE(wsjrdp_regular_full_fee_override,
      CASE payment_role
        WHEN 'RegularPayer::Group::Unit::Member'   THEN 3400 WHEN 'EarlyPayer::Group::Unit::Member'   THEN 3400
        WHEN 'RegularPayer::Group::Unit::Leader'   THEN 2400 WHEN 'EarlyPayer::Group::Unit::Leader'   THEN 2400
        WHEN 'RegularPayer::Group::Ist::Member'    THEN 2600 WHEN 'EarlyPayer::Group::Ist::Member'    THEN 2600
        WHEN 'RegularPayer::Group::Root::Member'   THEN 1600 WHEN 'EarlyPayer::Group::Root::Member'   THEN 1600
        WHEN 'RegularPayer::Group::Extern::Member' THEN 0    WHEN 'EarlyPayer::Group::Extern::Member' THEN 0
        ELSE CASE WHEN status IN ('registered', 'deregistration_noted', 'deregistered') THEN 0
                  ELSE 10000000 END
      END)
  SQL

  TOTAL_FEE_SQL = <<~SQL.squish
    COALESCE(wsjrdp_total_fee_override,
      GREATEST(#{REGULAR_FULL_FEE_SQL}
               - COALESCE(wsjrdp_total_fee_reduction, 0)
               - COALESCE(wsjrdp_extra_total_fee_reduction, 0), 0))
  SQL

  def change
    add_column :people, :wsjrdp_regular_full_fee_override, :decimal, precision: 20, scale: 3, null: true
    add_column :people, :wsjrdp_extra_total_fee_reduction, :decimal, precision: 20, scale: 3, null: true
    add_column :people, :wsjrdp_total_fee_override, :decimal, precision: 20, scale: 3, null: true

    add_column :people, :wsjrdp_regular_full_fee, :virtual,
      type: :decimal, precision: 20, scale: 3, as: REGULAR_FULL_FEE_SQL, stored: true
    add_column :people, :wsjrdp_total_fee, :virtual,
      type: :decimal, precision: 20, scale: 3, as: TOTAL_FEE_SQL, stored: true
  end
end
