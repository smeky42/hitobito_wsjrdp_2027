# frozen_string_literal: true

#  Copyright (c) 2025 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class WsjrdpFinAccount < ActiveRecord::Base
  include WsjrdpNumberHelper

  has_many :camt_transactions,
    foreign_key: "fin_account_id",
    inverse_of: :fin_account,
    class_name: "WsjrdpCamtTransaction",
    dependent: :restrict_with_error

  has_many :moss_balance_movements,
    foreign_key: "fin_account_id",
    inverse_of: :fin_account,
    class_name: "MossBalanceMovement",
    dependent: :restrict_with_error

  eur_attribute :opening_balance_eur, cents_attr: :opening_balance_cents
  eur_attribute :closing_balance_eur, cents_attr: :closing_balance_cents

  def transactions
    if transaction_type == "MossBalanceMovement"
      moss_balance_movements
    else
      camt_transactions
    end
  end

  def to_s
    if account_identification.present?
      "#{short_name} / #{account_identification}"
    else
      short_name
    end
  end

  def closing_balance_cents
    @closing_balance_cents ||= opening_balance_cents + transactions.map { |e| e.amount_cents }.sum
  end
end
