# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# A direct debit order with one Sammler and two debits, one of them returned
# (with its accounting entry), a credit transfer order and a return that
# finds no debit. All names, numbers and dates are invented.
shared_context "payment area" do
  before_all(setup_fixtures: true) {}

  let_it_be(:person) { people(:yp_a_1) }

  let_it_be(:account) do
    WsjrdpFinAccount.create!(short_name: "Beispielkonto", account_identification: "DE02 1203 0000 0000 2020 51",
      opening_balance_cents: 0, opening_balance_currency: "EUR", opening_balance_date: Date.new(2026, 1, 1))
  end
  let_it_be(:debit_order) do
    WsjrdpPaymentInitiation.create!(status: "xml_generated", sepa_schema: "pain.008.001.08",
      message_identification: "MSG-DD-1", number_of_transactions: 2, control_sum_cents: 30_000,
      initiating_party_iban: "DE02120300000000202051")
  end
  let_it_be(:transfer_order) do
    WsjrdpPaymentInitiation.create!(status: "xml_generated", sepa_schema: "pain.001.001.09",
      message_identification: "MSG-CT-1", number_of_transactions: 1, control_sum_cents: 5_000)
  end
  let_it_be(:payment_info) do
    WsjrdpDirectDebitPaymentInfo.create!(payment_initiation: debit_order, payment_information_identification: "PMT-1",
      debit_sequence_type: "RCUR", requested_collection_date: Date.new(2026, 5, 5), number_of_transactions: 2,
      control_sum_cents: 30_000)
  end
  let_it_be(:returned_debit, reload: true) { payment_debit("E2E-1", 20_000) }
  let_it_be(:paid_debit, reload: true) { payment_debit("E2E-2", 10_000, subject: people(:yp_a_2)) }
  let_it_be(:returned, reload: true) { camt_return(-200, endtoend_id: "E2E-1", return_reason: "MD06") }
  let_it_be(:return_entry) do
    payment_entry(-20_000, endtoend_id: "E2E-1", return_reason: "MD06", camt_transaction_id: returned.id)
  end
  let_it_be(:unassigned_return) do
    camt_return(-75, endtoend_id: "E2E-UNKNOWN", return_reason: "MS03", dbtr_name: "Konto Inhaberin", cdtr_name: "Wir")
  end

  def payment_debit(endtoend_id, cents, subject: person)
    WsjrdpDirectDebitPreNotification.create!(payment_initiation: debit_order, direct_debit_payment_info: payment_info,
      subject: subject, author: subject, amount_cents: cents, pre_notified_amount_cents: cents,
      description: "Beitrag", dbtr_name: "Muster", dbtr_iban: "DE02120300000000202051",
      debit_sequence_type: "RCUR", collection_date: Date.new(2026, 5, 5), payment_status: "xml_generated",
      endtoend_id: endtoend_id)
  end

  def payment_entry(cents, **attrs)
    AccountingEntry.create!(subject: person, author: person, amount_cents: cents, description: "Rücklastschrift",
      value_date: Date.new(2026, 5, 12), **attrs)
  end

  # A return as the bank statement holds it.
  def camt_return(amount, **attrs)
    WsjrdpCamtTransaction.create!(fin_account: account, camt_type: "CAMT052",
      account_identification: account.account_identification, account_servicer_reference: SecureRandom.hex(8),
      credit_debit_indication: "DBIT", bank_transaction_code: "PMNT+IDDT+UPDD", bank_transaction_code_dk: "NRTI+109",
      signed_base_amount: amount, base_currency: "EUR", value_date: Date.new(2026, 5, 5),
      booking_date: Date.new(2026, 5, 12), description: "Retoure", subject: person, **attrs)
  end

  # A returned credit transfer (an other return).
  def returned_transfer(**attrs)
    camt_return(150, credit_debit_indication: "CRDT", bank_transaction_code: "PMNT+ICDT+RRTN",
      bank_transaction_code_dk: "NRTI+159", return_reason: "MS03", endtoend_id: nil, **attrs)
  end

  # The bank's collective credit of a Sammler.
  def camt_credit(amount, info)
    WsjrdpCamtTransaction.create!(fin_account: account, camt_type: "CAMT052",
      account_identification: account.account_identification, account_servicer_reference: SecureRandom.hex(8),
      credit_debit_indication: "CRDT", bank_transaction_code: "PMNT+IDDT+ESDD",
      signed_base_amount: amount, base_currency: "EUR", value_date: Date.new(2026, 5, 5),
      booking_date: Date.new(2026, 5, 5), description: "Basislastschrift", direct_debit_payment_info: info,
      payment_initiation: info.payment_initiation)
  end
end
