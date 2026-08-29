# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# One booking (split) of a Moss card transaction: the fields that
# differ per split (line amount, expense account, note, ...). Belongs
# to exactly one MossCardTransaction and may reference its step-1
# DATEV booking (Sachkonto -> Sammelkreditor) 1:1. The step-2 clearing
# booking exists once per transaction and hangs off
# MossCardTransaction.
#
# Amounts follow doc/fin/money_conventions.md: `signed_base_amount` /
# `signed_transaction_amount` are the signed inputs (+ = inflow,
# i.e. refund), `base_amount` / `transaction_amount` / `debit_credit`
# are generated from them.
class MossCardTransactionBooking < ActiveRecord::Base
  belongs_to :card_transaction,
    class_name: "MossCardTransaction",
    inverse_of: :bookings,
    primary_key: :card_transaction_uuid,
    foreign_key: :card_transaction_uuid

  belongs_to :expense_datev_booking,
    optional: true,
    class_name: "DatevBooking",
    inverse_of: :moss_card_transaction_booking_as_expense

  # The ledger account of this booking, matched on its unique `number`; the
  # generated `account_type` column carries the target class (see the migration).
  belongs_to :account, polymorphic: true, optional: true,
    foreign_key: :account_number, primary_key: :number
end
