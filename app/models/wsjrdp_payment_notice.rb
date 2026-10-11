# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# A payment announced to a person: a refund paid to it (amount negative) or a
# claim it pays by transfer (amount positive), signed like an accounting
# entry. payment_code is the RF reference the remittance information carries,
# so a bank statement import can link the payment; a notice without a code
# (e.g. a refund through Moss) carries the empty string.
#
# The accounting entries carry the money, the notice what is due: every
# payment becomes an accounting entry with payment_notice_id, and
# booked_amount is their sum. The notice is
#
# - created: being prepared,
# - announced: shown to the person; from announced_at on amount, code,
#   remittance information, accounts and receipt stay, and a change means a
#   new notice replacing this one (replaces),
# - booked: settled, by the payments or by decision (a remainder waived),
# - canceled or deleted: given up, or made by mistake.
#
# A remainder may be asked for under a new code or the old one; a payment
# under an old code goes to the youngest open notice along replaces.
class WsjrdpPaymentNotice < ActiveRecord::Base
  STATUSES = %w[created announced booked canceled deleted].freeze
  FINAL_STATUSES = %w[booked canceled deleted].freeze

  # The payment reference payment_code comes from, if any; several notices
  # may share one, and a notice may carry a code without one.
  belongs_to :payment_reference, class_name: "WsjrdpPaymentReference", inverse_of: :payment_notices,
    optional: true

  # The empty string stands for "no code": the column is NOT NULL.
  attribute :payment_code, :string, default: ""

  validates :amount, presence: true
  validate :payment_code_of_reference, if: :payment_reference

  def payment_code=(value)
    super(value.to_s)
  end

  def payment_code? = payment_code.present?

  # Gives the notice a code from the stock (WsjrdpPaymentReference.assign!);
  # nothing is saved here. Call it where the notice is made, inside the
  # transaction that saves it.
  def assign_payment_reference!
    reference = WsjrdpPaymentReference.assign!
    self.payment_reference = reference
    self.payment_code = reference.payment_code
    reference
  end

  # What is still due: positive from the person, negative to it; nil while
  # the notice has no amount yet.
  def open_amount = amount && (amount - booked_amount.to_d)

  private

  def payment_code_of_reference
    return if payment_code == payment_reference.payment_code

    errors.add(:payment_code, :invalid)
  end
end
