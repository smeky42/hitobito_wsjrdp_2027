# frozen_string_literal: true

class WsjrdpDirectDebitPaymentInfo < ActiveRecord::Base
  has_many :accounting_entries,
    foreign_key: "direct_debit_payment_info_id",
    inverse_of: :direct_debit_payment_info,
    class_name: "AccountingEntry",
    dependent: :restrict_with_error
  has_many :direct_debit_pre_notifications,
    foreign_key: "direct_debit_payment_info_id",
    inverse_of: :direct_debit_payment_info,
    class_name: "WsjrdpDirectDebitPreNotification",
    dependent: :restrict_with_error
  belongs_to :payment_initiation,
    optional: true,
    class_name: "WsjrdpPaymentInitiation"
end
