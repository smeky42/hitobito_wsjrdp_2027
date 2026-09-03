# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# L3 of the unified Moss model: one row per SPLIT -- the grain DATEV books at and
# the only grain that reconciles cent-exact. No STI: a booking looks the same for
# every transaction kind.
#
# It carries exactly the dimensions Moss splits along -- Sachkonto
# (`account_number`), Kostenstelle, Sphaere and Buchungstext -- plus its share of
# the amount. Everything constant within the payment (creditor, currencies,
# exchange rate, and every header fact of the kind) is on the transaction,
# everything constant within one expense of a reimbursement (its name, text
# and purchase date) on the expense.
#
# `booking_unique_item_number` is the natural key and is CONSTRUCTED, not taken
# from the CSV: the Moss "Unique Item Number" suffix is a running counter that
# depends on the export's position, so it would not be stable across imports.
# The raw Moss value is kept in `other_moss_columns["Unique Item Number"]`
# (accessor `unique_item_number`).
#
# Two links live here: the step-1 DATEV booking (Sachkonto -> creditor) and the
# person whose CONTRIBUTION this booking concerns. The contribution link to
# accounting_entries points the other way (accounting_entries.moss_booking_id),
# because one booking may be split across several Beitragsbuchungen.
class MossBooking < ActiveRecord::Base
  include ActionView::Helpers::NumberHelper
  include ActionView::Helpers::TextHelper
  include ContractHelper
  include WsjrdpTransaction

  belongs_to :moss_transaction, inverse_of: :bookings
  belongs_to :moss_expense, inverse_of: :bookings, class_name: "MossExpense"

  # Step 1 of the Moss->DATEV chain (Sachkonto -> creditor), one per split.
  belongs_to :expense_datev_booking, optional: true, class_name: "DatevBooking",
    inverse_of: :moss_booking_as_expense

  # The ledger account of this split, matched on its unique `number`; the
  # generated `account_type` column carries the target class.
  belongs_to :account, polymorphic: true, optional: true,
    foreign_key: :account_number, primary_key: :number

  # The person whose Beitrag this booking concerns (renamed from the old
  # `subject` so it cannot be confused with the payment recipient on L1).
  belongs_to :contribution_subject, polymorphic: true, optional: true

  # A Moss booking may be split across SEVERAL contribution bookings (e.g. one
  # card payment for three registered letters -> three people). The sum of the
  # entries must stay <= this booking's amount; see amount_left_to_allocate.
  has_many :accounting_entries,
    inverse_of: :moss_booking,
    class_name: "AccountingEntry",
    dependent: :nullify

  attribute :accounting_entry_id, :integer

  delegate :moss_transaction_uuid, :currency, :currency_original, :exchange_rate,
    to: :moss_transaction, allow_nil: true

  # --- shared-concern adapter ------------------------------------------------
  # WsjrdpTransaction and SubjectLinking speak `subject` and `fin_account`, the
  # vocabulary of a bank statement row. Here that person role is called
  # `contribution_subject` -- so it cannot be confused with the payment
  # `recipient` on the transaction -- and the wallet hangs on the transaction.
  # The short names are adapted here and nowhere else, so the concerns stay
  # shared with WsjrdpCamtTransaction unchanged.
  def subject = contribution_subject

  def subject=(person)
    self.contribution_subject = person
  end

  def subject_id = contribution_subject_id

  def subject_type = contribution_subject_type

  delegate :fin_account, to: :moss_transaction, allow_nil: true

  # --- money -----------------------------------------------------------------

  # The signed EUR amount, under the name the shared statement view uses (the
  # same contract as WsjrdpCamtTransaction#amount_eur).
  def amount_eur = signed_base_amount

  def amount_cents = (signed_base_amount * 100).round

  def amount_eur_display
    number_to_currency(signed_base_amount, separator: ",", delimiter: ".", format: "%n")
  end

  def amount_with_currency = format_eur_de(signed_base_amount, currency || "EUR")

  # The split's share in the transaction currency -- shown only on a
  # foreign-currency payment, where it is the figure DATEV books (the plan,
  # section 4: never match on EUR).
  def original_amount_with_currency
    return nil if signed_transaction_amount.nil?

    format_eur_de(signed_transaction_amount, currency_original || currency || "EUR")
  end

  def foreign_currency? = moss_transaction&.foreign_currency? || false

  # --- other_moss_columns ----------------------------------------------------
  # Raw Moss fields of the split without a column, kept UNDER THEIR CSV HEADER;
  # these accessors map the header to a snake_case name. The amount mirrors
  # (also under their headers) have no accessor: the house columns carry them.
  OTHER_MOSS_TEXT_COLUMNS = {
    unique_item_number: "Unique Item Number",
    # the balance row of an invoice line / top-up: the ledger account's name
    # Moss's client code, per line (empty on every row today)
    unit_price: "Unit Price",
    quantity: "Quantity",
    vat_code: "VAT Code",
    vat_name: "VAT Name",
    vat_rate: "VAT Rate"
  }.freeze

  OTHER_MOSS_TEXT_COLUMNS.each do |name, key|
    define_method(name) { other_moss_columns[key].presence }
  end

  # The ledger account's name, from the standing data (the exports' copies of it
  # are not stored).
  def account_name = account.try(:name)

  # --- the three levels' texts ------------------------------------------------

  # German names of the three Moss levels, used wherever a text or comment is
  # tagged with the level it belongs to.
  LEVEL_NAMES = {transaction: "Transaktion", expense: "Ausgabe", booking: "Buchung"}.freeze

  # One entry per level, top down: [level, name, text]. The payment's name and
  # Buchungstext (per kind, see MossTransaction#display_name), the expense's
  # (a reimbursement's; the shell rows of the other kinds have neither), and
  # the split's text. A level with neither name nor text is dropped, a text
  # that merely repeats its own name is shown once, and the split's line goes
  # when its text only repeats the text of the level above, which a
  # reimbursement split's text mostly does and an invoice line's always.
  def text_lines
    lines = [
      [:transaction, moss_transaction&.display_name, moss_transaction&.display_text],
      [:expense, moss_expense&.display_name, moss_expense&.display_text],
      [:booking, nil, booking_posting_text]
    ].map { |level, name, text| [level, name.to_s.strip.presence, text.to_s.strip.presence] }
      .map { |level, name, text| [level, name, (text == name) ? nil : text] }
      .reject { |_level, name, text| name.nil? && text.nil? }
    if lines.size > 1 && lines.last.first == :booking
      _level, above_name, above_text = lines[-2]
      lines.pop if lines.last.last == (above_text || above_name)
    end
    lines
  end

  # How much of this booking is not yet allocated to contribution bookings.
  # Never negative in valid data -- see allocation_valid?.
  def amount_left_to_allocate_cents
    amount_cents - accounting_entries.sum(:amount_cents)
  end

  # The rule for the 1 : N contribution link: a booking may be allocated
  # partially, never beyond its own amount.
  def allocation_valid?
    accounting_entries.sum(:amount_cents).abs <= amount_cents.abs
  end

  # The comments of the payment and of the expense -- shown next to the
  # booking's own, which stays the only editable one. [[level name, text], ...],
  # blanks dropped.
  def parent_comments
    [[LEVEL_NAMES[:transaction], moss_transaction&.comment],
      [LEVEL_NAMES[:expense], moss_expense&.comment]]
      .select { |_level, text| text.present? }
  end

  # --- statement row interface (the fin_account view, shared with camt) ------
  # That view renders `text_lines` for a booking (one line per level, name
  # then Buchungstext); `description` and `note` are the plain-text forms for
  # links and for consumers that know only the camt shape.

  def self.line_text(name, text) = [name, text].compact.join(" – ")

  def description = text_lines.first&.then { |_level, name, text| self.class.line_text(name, text) } || ""

  # The further lines as [[level name, text], ...]; `note` is the same as plain text.
  def note_lines
    text_lines.drop(1).map { |level, name, text| [LEVEL_NAMES.fetch(level), self.class.line_text(name, text)] }
  end

  def note = note_lines.map { |level, text| "#{level}: #{text}" }.join("\n")

  # The texts a person's name may appear in: the split's and the expense's
  # Buchungstext, the claim's title (umlaut-correct, unlike the SEPA
  # reference), the account holder paid, and the SEPA reference.
  def description_for_subject_candidates
    [booking_posting_text, moss_expense&.expense_posting_text,
      moss_transaction&.transaction_name, moss_transaction&.recipient_name,
      moss_transaction&.payment_reference].compact.join(" ")
  end

  def subject_input_field_options = {input_field_type: "Person"}

  def value_date = moss_transaction&.payment_date

  def link_name(length: 80)
    pre = "[#{id}] "
    post = " (#{amount_eur_display})"
    length -= (pre.size + post.size)
    "#{pre}#{truncate(description.to_s, length: length)}#{post}"
  end
end
