# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# A payment reference ready for or given to a payment, made ahead by a script
# (wsjrdp_scripts: docs/payment_code.md) or by the wagon. payment_code is what
# the remittance information carries; for the type rf (an ISO 11649 creditor
# reference) it is RF, two check digits and the codeword. The row keeps the
# codeword scheme and the Reed-Solomon parameters the codeword was made with.
#
# A reference is available until it is assigned; a void one is never handed
# out. Payment notices refer to it by payment_reference_id, and the
# reference refers to nothing.
class WsjrdpPaymentReference < ActiveRecord::Base
  PAYMENT_CODE_TYPES = %w[rf].freeze
  STATUSES = %w[available assigned void].freeze
  ORIGINS = %w[script wagon].freeze

  has_many :payment_notices, class_name: "WsjrdpPaymentNotice", foreign_key: :payment_reference_id,
    inverse_of: :payment_reference, dependent: :restrict_with_error

  scope :available, -> { where(status: "available") }
  scope :assigned, -> { where(status: "assigned") }

  # As the check constraint of the table.
  validate :rf_form, if: -> { payment_code_type == "rf" }

  private

  def rf_form
    return if payment_code.to_s.match?(/\ARF\d{2}/) && payment_code.to_s[4..] == codeword

    errors.add(:payment_code, :invalid)
  end
end
