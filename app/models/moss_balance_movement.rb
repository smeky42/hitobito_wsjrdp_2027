# frozen_string_literal: true

#  Copyright (c) 2025 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class MossBalanceMovement < ActiveRecord::Base
  include ActionView::Helpers::NumberHelper
  include ActionView::Helpers::TextHelper
  include WsjrdpTransaction

  belongs_to :subject, polymorphic: true, optional: true
  belongs_to :fin_account,
    optional: true,
    class_name: "WsjrdpFinAccount"

  has_many :accounting_entries,
    inverse_of: :moss_balance_movement,
    class_name: "AccountingEntry",
    dependent: :nullify

  attribute :accounting_entry_id, :integer

  def amount_cents
    (amount * 100).to_i
  end

  def amount_currency
    currency
  end

  def description
    payment_reference
  end

  def description_for_subject_candidates
    [payment_reference, note].compact.join(" ")
  end

  def value_date = payment_date

  def amount_eur_display
    number_to_currency(amount, separator: ",", delimiter: ".", format: "%n")
  end

  def subject_input_field_options
    {input_field_type: "Person"}
  end

  def link_name(length: 80)
    pre = "[#{id}] "
    post = " (#{amount_eur_display})"
    length -= (pre.size + post.size)
    "#{pre}#{truncate(description, length: length)}#{post}"
  end
end
