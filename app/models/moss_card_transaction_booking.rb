# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# One booking (split) of a Moss card transaction: the fields that differ per
# split (line amount, expense account, category, note, ...). Belongs to exactly
# one MossCardTransaction and may reference the two per-booking DATEV bookings
# 1:1 (expense = step 1 Sachkonto -> Sammelkreditor; clearing = step 2
# Sammelkreditor -> Moss-Konto). See doc/moss_data_model.md (5.2).
class MossCardTransactionBooking < ActiveRecord::Base
  belongs_to :moss_card_transaction,
    inverse_of: :bookings,
    primary_key: :card_transaction_uuid,
    foreign_key: :card_transaction_uuid

  belongs_to :expense_datev_booking,
    optional: true,
    class_name: "DatevBooking",
    inverse_of: :expense_moss_card_transaction_booking

  belongs_to :clearing_datev_booking,
    optional: true,
    class_name: "DatevBooking",
    inverse_of: :clearing_moss_card_transaction_booking

  def amount_cents
    (amount * 100).to_i
  end
end
