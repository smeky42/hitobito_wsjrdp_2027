# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027
module Wsjrdp::Sync::MossApi
  # The dimensions (GET /v1/dimensions) into moss_dimensions. Moss keeps at
  # most 50 and returns them in one answer, without paging.
  class Dimensions < ListPart
    self.key = "moss_api.master_data.dimensions"
    self.path = "v1/dimensions"
    self.model = MossDimension
    self.uuid_column = "moss_dimension_uuid"

    def fetch(client)
      records = unique(Array(client.get(path)["data"]))
      {data_name => records, "paging" => {"total_items" => nil, "received" => records.size, "passes" => 1}}
    end

    private

    def attributes(record)
      {moss_dimension_uuid: record["id"], moss_organisation_uuid: record["organisationId"],
       name: text(record["name"]), erp_name: text(record["erpName"]), erp_id: text(record["erpId"]),
       status: record["status"], items_table: MossDimension::ITEMS_TABLES[record["id"]],
       moss_created_at: instant(record["createTime"]), moss_updated_at: instant(record["updateTime"]),
       moss_deleted_at: instant(record["deleteTime"])}
    end

    def label(record) = record["name"].presence || record["moss_dimension_uuid"]
  end
end
