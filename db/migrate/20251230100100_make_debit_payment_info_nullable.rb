# frozen_string_literal: true

#  Copyright (c) 2025 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class MakeDebitPaymentInfoNullable < ActiveRecord::Migration[7.1]
  def change
    # Allow partially filled debit payment infos
    change_column_null :wsjrdp_direct_debit_payment_infos, :creditor_id, true
    change_column_null :wsjrdp_direct_debit_payment_infos, :debit_sequence_type, true
    change_column_null :wsjrdp_direct_debit_payment_infos, :requested_collection_date, true

    # Allow creation of pre-notification rows without having a payment info yet.
    change_column_null :wsjrdp_direct_debit_pre_notifications, :comment, true
    change_column_null :wsjrdp_direct_debit_pre_notifications, :direct_debit_payment_info_id, true
  end
end
