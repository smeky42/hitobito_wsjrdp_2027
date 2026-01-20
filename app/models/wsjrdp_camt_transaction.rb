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

  belongs_to :subject, polymorphic: true, optional: true
  belongs_to :fin_account,
    optional: true,
    class_name: "WsjrdpFinAccount"

  has_one :accounting_entry,
    foreign_key: "camt_transaction_id",
    inverse_of: :camt_transaction,
    class_name: "AccountingEntry",
    dependent: :nullify

  eur_attribute :amount_eur, cents_attr: :amount_cents

  attribute :accounting_entry_id, :integer

  store_accessor :additional_info, :return_debit_status

  def return_status
    return_debit_status.presence || (return_reason.present? ? "in_review" : "none")
  end

  def return_status=(value)
    self.return_debit_status = value
  end

  def subject_input_field_options
    {input_field_type: "Person"}
  end

  def accounting_entry_id
    accounting_entry&.id
  end

  def accounting_entry_id=(value)
    if accounting_entry.present? && value != accounting_entry.id
      accounting_entry.camt_transaction_id = nil
    end
    if value.blank?
      self.accounting_entry = nil
    else
      self.accounting_entry = AccountingEntry.find_by(id: value)
      accounting_entry.camt_transaction_id = id
    end
    accounting_entry
  end

  def accounting_entries_for_subject(amount_cents: nil)
    return [] if subject.nil?
    entries = subject.accounting_entries
    entries = entries.select { |e| e.amount_cents == amount_cents } unless amount_cents.nil?
    entries
  end

  def accounting_entries_for_subject_with_matching_amount
    accounting_entries_for_subject(amount_cents: amount_cents)
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
    "#{id} #{truncate(description, length: length)} (#{amount_eur_display})"
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
