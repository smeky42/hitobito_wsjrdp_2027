# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027
module Wsjrdp::Sync::MossApi
  # The tax rates (GET /v1/tax-rates) into moss_tax_rates.
  class TaxRates < ListPart
    self.key = "moss_api.master_data.tax_rates"
    self.path = "v1/tax-rates"
    self.model = MossTaxRate
    self.uuid_column = "moss_tax_rate_uuid"
    self.sort_orders = %w[code -code].freeze

    private

    def attributes(record)
      {moss_tax_rate_uuid: record["id"], moss_organisation_uuid: record["organisationId"],
       tax_type: record["type"], country: record["country"], name: text(record["name"]), rate: record["rate"],
       code: text(record["code"]), reverse_charge: record["reverseCharge"], status: record["status"],
       moss_created_at: instant(record["createTime"]), moss_updated_at: instant(record["updateTime"])}
    end

    def label(record) = record["name"].presence || record["code"].presence || record["moss_tax_rate_uuid"]
  end
end
