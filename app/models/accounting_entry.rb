# frozen_string_literal: true

class AccountingEntry < ActiveRecord::Base
  include ActionView::Helpers::NumberHelper

  belongs_to :subject, polymorphic: true
  belongs_to :author, polymorphic: true

  belongs_to :direct_debit_payment_info, optional: true, class_name: "WsjrdpDirectDebitPaymentInfo"
  belongs_to :direct_debit_pre_notification, optional: true, class_name: "WsjrdpDirectDebitPreNotification"
  belongs_to :payment_initiation, optional: true, class_name: "WsjrdpPaymentInitiation"

  belongs_to :reversed_by, inverse_of: "reverses", optional: true, class_name: "AccountingEntry"
  belongs_to :reverses, inverse_of: "reversed_by", optional: true, class_name: "AccountingEntry"

  attribute :amount_eur, :float

  validates :description, presence: true
  validates :new_sepa_status, presence: true

  around_save :around_save_callback

  def person
    @person ||= ((subject_type == "Person") ? subject : Person.root)
  end

  def group
    @group ||= (person.primary_group_id.nil? ? Group.find(person.default_group_id) : person.primary_group)
  end

  def to_s
    "Transaktion #{id}"
  end

  def amount_eur
    if amount_cents.nil?
      nil
    else
      amount_cents.to_f / 100.0
    end
  end

  def amount_eur=(value)
    self.amount_cents = value.blank? ? nil : (value.to_f * 100.0).round
  end

  def amount_eur_display
    if amount_cents.nil?
      nil
    else
      eur = amount_cents.to_f / 100.0
      number_to_currency(eur, separator: ",", delimiter: ".", format: "%n")
    end
  end

  def new_sepa_status_display
    Settings.sepa_status[new_sepa_status]
  end

  private

  def around_save_callback
    if amount_cents.nil?
      self.amount_cents = 0
    end
    if created_at.nil?
      self.created_at = Time.now.getlocal
    end
    if updated_at.nil?
      self.updated_at = created_at
    end
    if value_date.nil?
      self.value_date = created_at.getlocal("+02:00").to_date
    end
    if end_to_end_identifier.blank?
      self.end_to_end_identifier = nil
    end
    yield
  end
end
