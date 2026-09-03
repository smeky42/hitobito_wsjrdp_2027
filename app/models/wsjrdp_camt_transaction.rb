# frozen_string_literal: true

#  Copyright (c) 2025 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class WsjrdpCamtTransaction < ActiveRecord::Base
  include ActionView::Helpers::TextHelper
  include WsjrdpNumberHelper
  include WsjrdpTransaction

  belongs_to :subject, polymorphic: true, optional: true

  # The subject (usually a Person) derived at import time from the payment
  # reference, kept separate from the (possibly hand-corrected) subject.
  # Details are recorded in imported_subject_link_meta.
  belongs_to :imported_subject, polymorphic: true, optional: true

  belongs_to :fin_account,
    optional: true,
    class_name: "WsjrdpFinAccount"

  has_many :accounting_entries,
    foreign_key: "camt_transaction_id",
    inverse_of: :camt_transaction,
    class_name: "AccountingEntry",
    dependent: :nullify

  # The DATEV booking this bank transaction is reconciled with. More
  # details are recorded in datev_booking_link_meta.
  belongs_to :datev_booking, optional: true

  # Money is stored on the house standard now (doc/fin/money_conventions.md):
  # signed_base_amount numeric(20,3) (+ = inflow), with base_amount = ABS and
  # debit_credit generated in the DB. The amount_eur* accessors are kept but
  # backed by signed_base_amount (EUR) -- the shared fin_account statement view
  # and link_name use amount_eur_display polymorphically with MossTransaction.
  def amount_eur
    signed_base_amount
  end

  def amount_eur=(value)
    self.signed_base_amount = value
  end

  def amount_eur_display
    eur_display_or_nil(signed_base_amount)
  end

  def amount_eur_input_field_options
    {value: eur_display_or_nil(signed_base_amount, delimiter: ""),
     type: "number", lang: "de-DE", step: 0.01, autocomplete: "off"}
  end

  # WsjrdpTransaction#accounting_entries_for_subject_with_matching_amount compares
  # against AccountingEntry.amount_cents (integer cents, hitobito heritage); camt
  # stores the numeric signed_base_amount, so convert at this cross-dialect edge.
  def accounting_entries_for_subject_with_matching_amount
    accounting_entries_for_subject(amount_cents: (signed_base_amount * 100).round)
  end

  attribute :accounting_entry_id, :integer

  store_accessor :additional_info, :return_debit_status

  def return_status
    return_debit_status.presence || (return_reason.present? ? "in_review" : "none")
  end

  def return_status=(value)
    self.return_debit_status = value
  end

  def description_for_subject_candidates
    description
  end

  def subject_input_field_options
    {input_field_type: "Person"}
  end

  def group
    @group ||= fetch_group
  end

  def try_skip?
    false
  end

  def skipped?
    false
  end

  def pre_booked?
    status != "BOOK"
  end

  def author_full_name
    nil
  end

  def link_name(length: 80)
    pre = "[#{id}] "
    post = " (#{amount_eur_display})"
    length -= (pre.size + post.size)
    "#{pre}#{truncate(description, length: length)}#{post}"
  end

  def short_dbtr
    s = [dbtr_name, dbtr_address, dbtr_iban].select { |e| !e.blank? }.join(", ")
    s.presence
  end

  private

  def fetch_group
    if subject.nil?
      Group.root
    elsif subject.primary_group_id.nil?
      Group.find(person.default_group_id)
    else
      subject.primary_group
    end
  end
end
