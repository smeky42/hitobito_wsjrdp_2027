# frozen_string_literal: true

# A payment order to the bank: one SEPA file (PAIN) sent from one of the
# contingent's accounts (Zahlungsverkehr, doc/fin/payments.md). Its kind
# (#kind) is a direct debit when its schema is pain.008 or direct debit
# payment infos belong to it, a credit transfer when its schema is pain.001;
# both at once is a conflict, neither unknown. #kind and .kind_sql say the
# same, the one in Ruby, the other in SQL for lists and filters.
class WsjrdpPaymentInitiation < ActiveRecord::Base
  DIRECT_DEBIT = "direct_debit"
  CREDIT_TRANSFER = "credit_transfer"
  CONFLICT = "conflict"
  UNKNOWN = "unknown"
  KINDS = [DIRECT_DEBIT, CREDIT_TRANSFER, CONFLICT, UNKNOWN].freeze

  DIRECT_DEBIT_SCHEMA_PREFIX = "pain.008"
  CREDIT_TRANSFER_SCHEMA_PREFIX = "pain.001"

  # The kind of the order in `table` (a table name or alias) as an SQL
  # expression.
  def self.kind_sql(table = table_name)
    debit = "(#{table}.sepa_schema LIKE '#{DIRECT_DEBIT_SCHEMA_PREFIX}%' OR EXISTS (SELECT 1 FROM " \
      "wsjrdp_direct_debit_payment_infos dd_kind WHERE dd_kind.payment_initiation_id = #{table}.id))"
    transfer = "#{table}.sepa_schema LIKE '#{CREDIT_TRANSFER_SCHEMA_PREFIX}%'"
    "CASE WHEN #{debit} AND #{transfer} THEN '#{CONFLICT}' WHEN #{debit} THEN '#{DIRECT_DEBIT}' " \
      "WHEN #{transfer} THEN '#{CREDIT_TRANSFER}' ELSE '#{UNKNOWN}' END"
  end

  # The kind, from a `kind` column the query selected (.kind_sql), else
  # worked out here.
  def kind
    return self[:kind] if has_attribute?(:kind)

    schema = sepa_schema.to_s
    debit = schema.start_with?(DIRECT_DEBIT_SCHEMA_PREFIX) || direct_debit_payment_infos.exists?
    transfer = schema.start_with?(CREDIT_TRANSFER_SCHEMA_PREFIX)
    if debit && transfer then CONFLICT
    elsif debit then DIRECT_DEBIT
    elsif transfer then CREDIT_TRANSFER
    else
      UNKNOWN
    end
  end

  def direct_debit? = kind == DIRECT_DEBIT

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
  # The bank's collective credits of this order's Sammler.
  has_many :camt_transactions,
    foreign_key: "payment_initiation_id",
    inverse_of: :payment_initiation,
    class_name: "WsjrdpCamtTransaction",
    dependent: :nullify
end
