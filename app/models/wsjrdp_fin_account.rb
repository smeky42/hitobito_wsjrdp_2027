# frozen_string_literal: true

#  Copyright (c) 2025 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class WsjrdpFinAccount < ActiveRecord::Base
  include WsjrdpNumberHelper

  has_many :camt_transactions,
    foreign_key: "fin_account_id",
    inverse_of: :fin_account,
    class_name: "WsjrdpCamtTransaction",
    dependent: :restrict_with_error

  # The wallet holds EVERY Moss kind (card payments included) of
  # payment/expense.
  has_many :moss_transactions,
    foreign_key: "fin_account_id",
    inverse_of: :fin_account,
    class_name: "MossTransaction",
    dependent: :restrict_with_error

  # The wallet STATEMENT is a list of bookings, not of payments: the booking is
  # the row the FIN views act on (it carries the contribution subject, the
  # accounting-entry link and the deny list) and the only one with a route of
  # its own. Summing them gives the same balance as summing the payments.
  has_many :moss_bookings, through: :moss_transactions, source: :bookings

  # The bookkeeping account this bank account / wallet maps to,
  # referenced by its `number` (not id). Polymorphic to allow pointing
  # at any account class.
  belongs_to :bookkeeping_account,
    polymorphic: true,
    primary_key: :number,
    foreign_key: :bookkeeping_account_number,
    optional: true

  eur_attribute :opening_balance_eur, cents_attr: :opening_balance_cents
  eur_attribute :closing_balance_eur, cents_attr: :closing_balance_cents

  # `transaction_type` is the stored discriminator of the account; its value is
  # still the pre-unification class name, so it is treated as an opaque marker
  # for "this is the Moss wallet".
  def transactions
    if transaction_type == "MossBalanceMovement"
      moss_bookings
    else
      camt_transactions
    end
  end

  def to_s
    if account_identification.present?
      "#{short_name} / #{account_identification}"
    else
      short_name
    end
  end

  def closing_balance_cents
    # A statement row is either a camt transaction (bank accounts) or
    # a Moss booking (the wallet). Both expose the signed EUR amount
    # as `amount_eur`, so one sum covers both; the account's own
    # balance is kept in integer cents (hitobito heritage), hence the
    # conversion at this edge.
    @closing_balance_cents ||=
      opening_balance_cents + (transactions.sum(&:amount_eur) * 100).round
  end
end
