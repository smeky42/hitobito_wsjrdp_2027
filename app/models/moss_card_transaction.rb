# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Moss card transactions, imported from a Moss Custom-CSV export. One
# row per Moss `Transaction ID`; the per-split fields live in
# moss_card_transaction_bookings.
#
# `moss_record_url`, `moss_attachment_url` and `transaction_id_pdf_filename` have
# no own column: they are derivable from `card_transaction_uuid`. The importer
# only stores a value in `other_moss_columns` if it deviates from the derived one;
# the reader methods below return that override, otherwise the derived value.
class MossCardTransaction < ActiveRecord::Base
  # Base URL of a Moss transaction record; the rest is derivable from the UUID.
  MOSS_RECORD_URL_PREFIX = "https://getmoss.com/app/transactions/all/"

  # Polymorphic like moss_balance_movements / wsjrdp_camt_transactions carry it
  # (usually the cardholder as a Person); set manually, never by the import.
  belongs_to :subject, polymorphic: true, optional: true

  # Step-2 of the Moss->DATEV chain (Moss-Konto 36100 ->
  # Sammelkreditor 700002).  It is posted once per transaction with
  # the transaction total, so the link lives here and not on the
  # individual bookings (see doc/fin/moss_data_model.md).
  belongs_to :clearing_datev_booking,
    optional: true,
    class_name: "DatevBooking",
    inverse_of: :moss_card_transaction_as_clearing

  # The three accounts of the Moss->DATEV chain, matched on their
  # unique `number` like the booking lines are; the generated
  # `*_type` columns carry the target class (see the migration).
  # Optional because the master-data tables are imported separately
  # and a number may not be resolvable yet.
  belongs_to :supplier_account, polymorphic: true, optional: true,
    foreign_key: :supplier_account_number, primary_key: :number
  belongs_to :moss_balance_account, polymorphic: true, optional: true,
    foreign_key: :moss_balance_account_number, primary_key: :number
  belongs_to :cash_in_transit_account, polymorphic: true, optional: true,
    foreign_key: :cash_in_transit_account_number, primary_key: :number

  # Bookings reference the transaction by its natural key
  # (card_transaction_uuid).
  has_many :bookings,
    inverse_of: :card_transaction,
    class_name: "MossCardTransactionBooking",
    primary_key: :card_transaction_uuid,
    foreign_key: :card_transaction_uuid,
    dependent: :destroy

  # The transaction-currency counterpart of
  # `signed_total_base_amount`, which is stored. Not a column: it is
  # only meaningful when all bookings share one transaction currency
  # (they do -- one card payment, one merchant).  Enumerable#sum on
  # purpose: works off the preloaded association instead of firing an
  # extra query per transaction in list views.
  def signed_total_transaction_amount = bookings.sum(&:signed_transaction_amount)

  # Moss record URL, e.g. https://getmoss.com/app/transactions/all/<uuid>
  def moss_record_url
    other_moss_columns["moss_record_url"] || derived_moss_record_url
  end

  # Moss attachment URL = the record URL without the "https://" scheme.
  def moss_attachment_url
    other_moss_columns["moss_attachment_url"] || derived_moss_record_url.delete_prefix("https://")
  end

  # File name of the combined receipt PDF in the attachments export, "<uuid>.pdf".
  def transaction_id_pdf_filename
    other_moss_columns["transaction_id_pdf_filename"] || "#{card_transaction_uuid}.pdf"
  end

  private

  def derived_moss_record_url
    "#{MOSS_RECORD_URL_PREFIX}#{card_transaction_uuid}"
  end
end
