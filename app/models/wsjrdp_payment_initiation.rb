# frozen_string_literal: true

class WsjrdpPaymentInitiation < ActiveRecord::Base
  has_many :accounting_entries,
    foreign_key: "payment_initiation_id",
    inverse_of: :payment_initiation,
    dependent: :restrict_with_error
  has_many :direct_debit_payment_infos,
    foreign_key: "payment_initiation_id",
    class_name: "WsjrdpDirectDebitPaymentInfo",
    inverse_of: :payment_initiation,
    dependent: :restrict_with_error
end
