# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# A tax rate in Moss (API /v1/tax-rates).
class MossTaxRate < ActiveRecord::Base
  include MossSyncedRecord

  validates :moss_tax_rate_uuid, presence: true, uniqueness: true

  # rubocop:disable Rails/HasManyOrHasOneDependent -- references may dangle
  has_many :suppliers, class_name: "WsjrdpPersonalAccount",
    primary_key: :moss_tax_rate_uuid, foreign_key: :default_moss_vat_rate_uuid, inverse_of: :default_moss_vat_rate
  # rubocop:enable Rails/HasManyOrHasOneDependent

  def to_s = name.presence || code.presence || moss_tax_rate_uuid
end
