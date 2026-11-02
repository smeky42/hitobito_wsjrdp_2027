# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The original of a return that is no returned direct debit
# (doc/fin/payments.md): the bank transaction it brought back, linked both ways
# -- the return's reverses_id, the original's reversed_by_id.
#
# The candidates of a return are the bank transactions that could be its
# original: the opposite amount exactly (no partial returns), within
# WINDOW_DAYS before the return, no return themselves, not deleted, replaced
# or brought back by another return, and of the kind the return's kind says
# (RULES). Each gets a score from what else matches: the end-to-end id, the IBAN
# of the other party (or, for a recredited direct debit, its mandate), the
# name, and how close in time.
module Fin::ReturnOriginals
  WINDOW_DAYS = 90

  # By return_kind: the side of the original and its ISO families, and the
  # party whose IBAN and name it shares with the return.
  RULES = {
    "credit_transfer" => {debit_credit: "D", families: %w[ICDT IRCT], party: "cdtr"},
    "received_credit_transfer" => {debit_credit: "C", families: %w[RCDT RRCT], party: "dbtr"},
    "received_direct_debit" => {debit_credit: "D", families: %w[RDDT], party: "cdtr", mandate: true},
    "other" => {}
  }.freeze

  # One candidate: the bank transaction, its score and what matched.
  Candidate = Data.define(:transaction, :score, :matches, :days) do
    delegate :id, to: :transaction
  end

  module_function

  def candidates(ret)
    rule = RULES[ret.return_kind]
    return [] unless rule && ret.signed_base_amount

    scope(ret, rule).map { |tx| candidate(ret, tx, rule) }
      .sort_by { |c| [-c.score, c.days, -c.id] }
  end

  # Whether `original` may be linked as the original of `ret`.
  def candidate?(ret, original) = candidates(ret).any? { |c| c.id == original.id }

  def link!(ret, original)
    WsjrdpCamtTransaction.transaction do
      unlink!(ret)
      ret.update!(reverses_id: original.id)
      original.update!(reversed_by_id: ret.id)
    end
  end

  def unlink!(ret)
    WsjrdpCamtTransaction.transaction do
      original = ret.reverses
      original.update!(reversed_by_id: nil) if original&.reversed_by_id == ret.id
      ret.update!(reverses_id: nil)
    end
  end

  def scope(ret, rule)
    date = ret.booking_date || ret.value_date
    scope = WsjrdpCamtTransaction.where(deleted_at: nil, replaced_by_id: nil, return_kind: nil)
      .where.not(id: ret.id)
      .where(signed_base_amount: -ret.signed_base_amount)
      .where(value_date: (date - WINDOW_DAYS)..date)
      .where("reversed_by_id IS NULL OR reversed_by_id = ?", ret.id)
    scope = scope.where(debit_credit: rule[:debit_credit]) if rule[:debit_credit]
    scope = scope.where(bank_transaction_family: rule[:families]) if rule[:families]
    scope
  end

  def candidate(ret, tx, rule)
    party = rule[:party]
    matches = []
    matches << :endtoend if usable_endtoend?(ret) && tx.endtoend_id == ret.endtoend_id
    matches << :iban if party && ret.public_send(:"#{party}_iban").present? &&
      tx.public_send(:"#{party}_iban") == ret.public_send(:"#{party}_iban")
    matches << :mandate if rule[:mandate] && ret.mandate_id.present? && tx.mandate_id == ret.mandate_id
    matches << :name if party && ret.public_send(:"#{party}_name").present? &&
      tx.public_send(:"#{party}_name").to_s.casecmp?(ret.public_send(:"#{party}_name").to_s)
    days = ((ret.booking_date || ret.value_date) - tx.value_date).to_i
    score = 50 + {endtoend: 50, iban: 30, mandate: 30, name: 10}.sum { |key, points| matches.include?(key) ? points : 0 } +
      [10 - (days / 9), 0].max
    Candidate.new(transaction: tx, score: [score, 100].min, matches: matches, days: days)
  end

  def usable_endtoend?(ret) = ret.endtoend_id.present? && ret.endtoend_id != "NOTPROVIDED"
end
