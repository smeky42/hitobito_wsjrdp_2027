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

  eur_attribute :amount_eur, cents_attr: :amount_cents

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
