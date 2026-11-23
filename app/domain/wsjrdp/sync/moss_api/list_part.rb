# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027
module Wsjrdp::Sync::MossApi
  # A part that copies one Moss list into one table keyed by Moss UUID
  # (Wsjrdp::Sync::MossTable). A subclass names the list, the table and how
  # a record maps onto its columns, and may add notices.
  class ListPart < Wsjrdp::Sync::Part
    self.source = KIND
    # Removing every row, or more than this share and MANY_REMOVED_MIN, is a
    # warning: Moss may have answered too little.
    MANY_REMOVED_SHARE = 0.1
    MANY_REMOVED_MIN = 5
    # The key prefix of a change to a person (#person_changes).
    PERSON_KEY = "person:"

    class_attribute :path, :model, :uuid_column, instance_writer: false
    # The column a notice is about, by its code: its chip stands at that
    # column's value in a change's detail.
    class_attribute :notice_fields, instance_writer: false, default: {}.freeze
    # Records per request. The organisation lists allow 1000 (OpenAPI spec),
    # so they come in one page: no offset paging, no repeated records.
    class_attribute :page_size, instance_writer: false, default: 1000

    def self.data_name = path.split("/").last

    # One pass may repeat a record and skip another (offset paging, sorted
    # by name only); when records are missing, a pass in the other order fills in.
    def fetch(client)
      records = unique(client.all(path, {sort: "name"}, page_size: page_size))
      total = client.total_items(path)
      again = total && records.size < total
      records = unique(records + client.all(path, {sort: "-name"}, page_size: page_size)) if again
      {data_name => records, "paging" => {"total_items" => total, "received" => records.size, "passes" => again ? 2 : 1}}
    end

    def plan(data)
      records = records(data)
      table = table(records)
      changes = table.changes { |record| label(record) } + person_changes(records)
      notices = []
      unless complete?(data)
        changes = changes.reject { |change| change.action == "remove" }
        notices << warning("incomplete", {}, table: self.class.label, received: records.size,
          total: data.dig("paging", "total_items"))
      end
      Wsjrdp::Sync::Plan.new(changes: changes, warnings: notices + notices(records, changes, table))
    end

    # The rows written (Wsjrdp::Sync::Stats).
    def apply(data, plan)
      people, own = plan.changes.partition { |change| change.key.to_s.start_with?(PERSON_KEY) }
      table(records(data)).apply(own, context.now).add("updated", apply_person_changes(people))
    end

    private

    def data_name = self.class.data_name

    def records(data) = Array(data[data_name])

    def unique(records) = records.uniq { |record| record["id"] }

    # Whether Moss gave every record it said it has.
    def complete?(data)
      total = data.dig("paging", "total_items")
      total.nil? || records(data).size >= total
    end

    def table(records)
      rows = records.to_h { |record| [record["id"], attributes(record)] }
      Wsjrdp::Sync::MossTable.new(model, uuid_column, rows)
    end

    # Changes to people besides the table, keyed "person:<id>".
    def person_changes(_records) = []

    # How many people were written.
    def apply_person_changes(_changes) = 0

    # {column => value} of one Moss record.
    def attributes(_record) = raise(NotImplementedError)

    # The text shown for a record (its attributes or its row).
    def label(_record) = raise(NotImplementedError)

    def notices(records, changes, table)
      removed = changes.select { |change| change.action == "remove" }
      current = table.current_count
      many = removed.size > MANY_REMOVED_MIN && removed.size > current * MANY_REMOVED_SHARE
      return [] if removed.empty? || (removed.size != current && !many)

      [warning("many_removed", removed.to_h { |change| [change.key, change.label] }, table: self.class.label)]
    end

    # The UUIDs of another part: what this run fetched, else its rows in
    # Moss; so writing an earlier part never changes a later part's plan.
    def known(model, uuid_column, part_key, data_name)
      fetched = context.data_of(part_key)
      return Set.new(Array(fetched[data_name]).pluck("id")) if fetched

      Set.new(model.in_moss.pluck(uuid_column))
    end

    # {key => "label → reference"} of the records whose field names nothing known.
    def dangling(records, field, known)
      records.select { |record| record[field] && !known.include?(record[field]) }
        .to_h { |record| [record["id"], "#{item_label(record)} → #{record[field]}"] }
    end

    def items(records) = records.to_h { |record| [record["id"], item_label(record)] }

    # How a record is named in a notice: its name (else its UUID), and its status.
    def item_label(record)
      [label(record).presence || record["id"], ("Status: #{record["status"]}" if record["status"].present?)].compact.join(" · ")
    end
  end
end
