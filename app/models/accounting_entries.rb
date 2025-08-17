class AccountingEntries < ActiveRecord::Base
  include ActionView::Helpers::NumberHelper

  attribute :amount_eur, :float

  validates :description, presence: true
  validates :sepa_status, presence: true

  around_save :around_save_callback

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

  def amount_eur_string
    if amount_cents.nil?
      nil
    else
      eur = amount_cents.to_f / 100.0
      number_to_currency(eur, separator: ",", delimiter: ".", format: "%n")
    end
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
