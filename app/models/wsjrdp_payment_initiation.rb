# frozen_string_literal: true

class WsjrdpPaymentInitiation < ActiveRecord::Base
  has_many :accounting_entries,
    foreign_key: "payment_initiation_id",
    inverse_of: :payment_initiation,
    class_name: "AccountingEntry",
    dependent: :restrict_with_error
  has_many :direct_debit_payment_infos,
    foreign_key: "payment_initiation_id",
    inverse_of: :payment_initiation,
    class_name: "WsjrdpDirectDebitPaymentInfo",
    dependent: :restrict_with_error
  has_many :direct_debit_pre_notifications,
    foreign_key: "direct_debit_payment_info_id",
    inverse_of: :direct_debit_payment_info,
    class_name: "WsjrdpDirectDebitPreNotification",
    dependent: :restrict_with_error
end
