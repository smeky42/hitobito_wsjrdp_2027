# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# What the edit pages of a debit (/fin/payments/debits/:id/edit and
# /fin/pn/:id/edit, Fin::DebitPages) let change: while it is only announced
# (pre_notified), its payment data; once it is in a SEPA file or skipped, the
# comment alone. The order, Sammler and group header hold the sequence type,
# the collection date, the creditor and the creditor id; the status follows
# the run. The manage tier (:admin_finance on the pre-notification)
# may also set its status, in any status, and -- while it is only announced --
# its mandate reference. Each field with the input it gets
# (Fin::DetailHelper).
module Fin::DebitEditing
  PRE_NOTIFIED = "pre_notified"

  WHILE_PRE_NOTIFIED = {
    try_skip: :check_box,
    amount_eur: :amount,
    description: :wide_text,
    comment: :textarea,
    endtoend_id: :wide_text,
    dbtr_name: :wide_text,
    dbtr_iban: :wide_text,
    dbtr_bic: :text,
    dbtr_address: :wide_text,
    mandate_date: :date
  }.freeze

  # What the manage tier may change on top: the status always, the mandate
  # reference while only announced.
  MANAGE_ALWAYS = {payment_status: :wide_select}.freeze
  MANAGE_WHILE_PRE_NOTIFIED = {mandate_id: :wide_text}.freeze

  AFTERWARDS = {comment: :textarea}.freeze

  module_function

  # {attribute => input} of what may change in the debit's status; `manage:`
  # whether the viewer holds the manage tier.
  def fields(debit, manage: false)
    pre_notified = debit.payment_status == PRE_NOTIFIED
    fields = pre_notified ? WHILE_PRE_NOTIFIED : AFTERWARDS
    return fields unless manage

    fields.merge(MANAGE_ALWAYS).merge(pre_notified ? MANAGE_WHILE_PRE_NOTIFIED : {})
  end

  # The statuses a debit can be set to, as the select offers them
  # (Settings.pre_notification_payment_status).
  def statuses = Settings.pre_notification_payment_status.to_h.transform_keys(&:to_s)

  # The params the update takes: the amount as the money input sends it
  # ("1.234,56"); a status only one of .statuses.
  def permitted(debit, params, manage: false)
    attrs = params.permit(fields(debit, manage: manage).keys)
    attrs[:amount_eur] = Fin::MoneyInput.normalize(attrs[:amount_eur]) if attrs.key?(:amount_eur)
    attrs.delete(:payment_status) if attrs.key?(:payment_status) && !statuses.key?(attrs[:payment_status])
    attrs
  end
end
