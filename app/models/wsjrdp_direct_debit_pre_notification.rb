# frozen_string_literal: true

#  Copyright (c) 2025 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class WsjrdpDirectDebitPreNotification < ActiveRecord::Base
  include ActionView::Helpers::TextHelper
  include WsjrdpNumberHelper

  belongs_to :direct_debit_payment_info,
    optional: true,
    class_name: "WsjrdpDirectDebitPaymentInfo"
  belongs_to :payment_initiation,
    optional: true,
    class_name: "WsjrdpPaymentInitiation"
  belongs_to :subject, polymorphic: true
  belongs_to :author, polymorphic: true

  has_one :accounting_entry,
    foreign_key: "direct_debit_pre_notification_id",
    inverse_of: :direct_debit_pre_notification,
    class_name: "AccountingEntry",
    dependent: :restrict_with_error

  has_many :notes, dependent: :destroy, as: :subject

  validates :amount_eur, presence: true
  validates :description, presence: true

  def person
    @person ||= ((subject_type == "Person") ? subject : Person.root)
  end

  def group
    @group ||= (person.primary_group_id.nil? ? Group.find(person.default_group_id) : person.primary_group)
  end

  eur_attribute :amount_eur, cents_attr: :amount_cents
  eur_attribute :pre_notified_amount_eur, cents_attr: :pre_notified_amount_cents

  def link_name(length: 80)
    "#{id} #{truncate(description, length: length)} (#{amount_eur_display})"
  end

  def try_skip?
    try_skip
  end

  def pre_booked?
    payment_status == "pre_notified"
  end

  def skipped?
    payment_status == "skipped"
  end

  def value_date
    collection_date
  end

  def short_dbtr
    s = [dbtr_name, dbtr_address, dbtr_iban].select { |e| !e.blank? }.join(", ")
    s.presence
  end

  def author_full_name
    if author_id.blank? || author_type != "Person" || author_id < 2
      nil
    else
      fall_back = "Unbekannte Person (id #{author_id})"
      begin
        if author.blank?
          fall_back
        else
          author.full_name
        end
      rescue
        fall_back
      end
    end
  rescue
    nil
  end
end
