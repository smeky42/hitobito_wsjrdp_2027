# frozen_string_literal: true

class WsjrdpDirectDebitPreNotification < ActiveRecord::Base
  has_one :accounting_entry,
    foreign_key: "direct_debit_pre_notification_id",
    inverse_of: :direct_debit_pre_notification,
    class_name: "AccountingEntry",
    dependent: :restrict_with_error
  belongs_to :direct_debit_payment_info,
    optional: true,
    class_name: "WsjrdpDirectDebitPaymentInfo"
  belongs_to :payment_initiation,
    optional: true,
    class_name: "WsjrdpPaymentInitiation"
  belongs_to :subject, polymorphic: true
  belongs_to :author, polymorphic: true
end
