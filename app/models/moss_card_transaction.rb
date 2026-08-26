# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Moss card transaction (Kartentransaktion), imported from the Moss Custom-CSV
# "WSJ27" export. One row per Moss `Transaction ID`; the per-split fields live in
# moss_card_transaction_bookings. See migration
# 20260823000100_add_moss_card_transactions.rb and doc/moss_data_model.md (5.2).
#
# `moss_record_url`, `moss_attachment_url` and `transaction_id_pdf_filename` have
# no own column: they are derivable from `card_transaction_uuid`. The importer
# only stores a value in `other_columns` if it deviates from the derived one;
# the reader methods below return that override, otherwise the derived value.
class MossCardTransaction < ActiveRecord::Base
  # Base URL of a Moss transaction record; the rest is derivable from the UUID.
  MOSS_RECORD_URL_PREFIX = "https://getmoss.com/app/transactions/all/"

  belongs_to :person, optional: true
  belongs_to :fin_account, optional: true, class_name: "WsjrdpFinAccount"

  # Bookings reference the transaction by its natural key (card_transaction_uuid).
  has_many :bookings,
    inverse_of: :moss_card_transaction,
    class_name: "MossCardTransactionBooking",
    primary_key: :card_transaction_uuid,
    foreign_key: :card_transaction_uuid,
    dependent: :destroy

  # Moss record URL, e.g. https://getmoss.com/app/transactions/all/<uuid>
  def moss_record_url
    other_columns["moss_record_url"] || derived_moss_record_url
  end

  # Moss attachment URL = the record URL without the "https://" scheme.
  def moss_attachment_url
    other_columns["moss_attachment_url"] || derived_moss_record_url.delete_prefix("https://")
  end

  # File name of the combined receipt PDF in the attachments export, "<uuid>.pdf".
  def transaction_id_pdf_filename
    other_columns["transaction_id_pdf_filename"] || "#{card_transaction_uuid}.pdf"
  end

  private

  def derived_moss_record_url
    "#{MOSS_RECORD_URL_PREFIX}#{card_transaction_uuid}"
  end
end
