# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027
module Wsjrdp::Sync::MossApi
  # A part that copies one Moss list into a master-data table keyed by
  # number. A subclass names the list, the table, how a Moss code becomes a
  # number and which further columns a record fills.
  class MasterPart < ListPart
    self.uuid_column = "moss_uuid"
    self.notice_fields = {"name_changed" => "name"}.freeze
    self.many_removed_code = "many_cleared"

    # Keys in lower case. A row found by number may have its UUID by now: each
    # row stands under both keys.
    def self.records_for(keys)
      prefix = Wsjrdp::Sync::MasterTable::NUMBER_KEY
      numbers, uuids = keys.partition { |key| key.to_s.start_with?(prefix) }
      by_number = model.where("LOWER(number) IN (?)", numbers.map { |key| key.delete_prefix(prefix) }.presence || [nil])
      model.where(moss_uuid: uuids).or(by_number).each_with_object({}) do |record, by_key|
        by_key["#{prefix}#{record.number.downcase}"] = record
        by_key[record.moss_uuid.downcase] = record if record.moss_uuid
      end
    end

    # The status as the master-data tables keep it: active, deactivated, deleted.
    def self.status(value) = value.to_s.downcase.presence

    # The number a Moss code stands for, nil when it fits no row of the table.
    def self.number(code) = code&.to_s&.strip.presence

    private

    def number(code) = self.class.number(code)

    def attributes(record)
      {moss_uuid: record["id"], number: number(record["code"]), name: text(record["name"]),
       moss_status: self.class.status(record["status"]), moss_organisation_uuid: record["organisationId"],
       moss_created_at: instant(record["createTime"]), moss_updated_at: instant(record["updateTime"])}
        .merge(more_attributes(record))
    end

    def more_attributes(_record) = {}

    def label(record) = [record["number"], record["name"]].compact_blank.join(" ")

    def item_label(record) = [record["code"], record["name"]].compact_blank.join(" ").presence || record["id"]

    def table(records)
      rows = valid(records).to_h { |record| [record["id"], attributes(record)] }
      Wsjrdp::Sync::MasterTable.new(model, rows, skipped: (records - valid(records)).pluck("id"))
    end

    def valid(records) = records.select { |record| number(record["code"]) }

    def notices(records, changes, table)
      super + [warning("invalid_number", items(records - valid(records)), table: self.class.label),
        warning("number_conflict", conflict_items(table.conflicts), table: self.class.label),
        important("name_changed", name_changes(changes), table: self.class.label)].reject { |notice| notice.keys.empty? }
    end

    # {Moss UUID => "<why>: Moss Nr. …, UUID … · Hitobito Nr. …, UUID …"}
    def conflict_items(conflicts)
      conflicts.to_h do |conflict|
        hitobito = conflict.rows.map { |row| "Nr. #{row.number}, UUID #{row.moss_uuid || "–"}" }.join(" und ").presence || "–"
        [conflict.uuid, "#{I18n.t("fin.sync.conflicts.#{conflict.kind}")}: Moss Nr. #{conflict.number}, " \
          "UUID #{conflict.uuid} · Hitobito #{hitobito}"]
      end
    end

    # {key => "old → new"} of the rows Moss renames.
    def name_changes(changes)
      changes.select { |change| change.action == "update" && change.values["name"]&.first.present? }
        .to_h { |change| [change.key, change.values["name"].join(" → ")] }
    end

    # {Moss UUID => number} of another master part: what this run fetched,
    # else the rows in Moss.
    def numbers_of(part)
      fetched = context.data_of(part.key)
      return Array(fetched[part.data_name]).to_h { |record| [record["id"], part.number(record["code"])] } if fetched

      part.model.where.not(moss_uuid: nil).where.not(moss_status: nil).pluck(:moss_uuid, :number).to_h
    end
  end
end
