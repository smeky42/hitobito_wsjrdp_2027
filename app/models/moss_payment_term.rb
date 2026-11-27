# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# A payment term in Moss (API /v1/payment-terms).
class MossPaymentTerm < ActiveRecord::Base
  include MossSyncedRecord

  validates :moss_payment_term_uuid, presence: true, uniqueness: true

  # rubocop:disable Rails/HasManyOrHasOneDependent -- references may dangle
  has_many :suppliers, class_name: "WsjrdpPersonalAccount",
    primary_key: :moss_payment_term_uuid, foreign_key: :default_moss_payment_term_uuid, inverse_of: :default_moss_payment_term
  # rubocop:enable Rails/HasManyOrHasOneDependent

  def to_s = description.presence || code.presence || moss_payment_term_uuid
end
