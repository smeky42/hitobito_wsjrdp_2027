# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp::Sync
  # Compares a list from Moss with a table keyed by Moss UUID that has
  # last_seen_at and moss_removed_at (MossSyncedRecord), and writes the
  # difference. A row Moss no longer returns is marked, never deleted; a
  # row that comes back is restored.
  class MossTable
    # rows: {uuid => attributes}, as the table's columns, the UUID included.
    def initialize(model, uuid_column, rows)
      @model = model
      @uuid_column = uuid_column.to_s
      uuid = @model.type_for_attribute(@uuid_column)
      @rows = rows.to_h { |key, attributes| [uuid.cast(key), cast(attributes.stringify_keys)] }
    end

    def existing = @existing ||= @model.all.index_by { |record| record[@uuid_column] }

    # The changes; label gives the text shown for a record or attributes.
    def changes(&label)
      seen = @rows.filter_map do |uuid, attributes|
        row = existing[uuid]
        next change("create", uuid, label.call(attributes), attributes) if row.nil?

        diff = attributes.filter_map { |column, value| [column, [row[column], value]] unless row[column] == value }.to_h
        action = if row.moss_removed_at then "restore"
        elsif diff.any? then "update"
        end
        change(action, uuid, label.call(row), diff) if action
      end
      removed = existing.values.select { |row| row.moss_removed_at.nil? && !@rows.key?(row[@uuid_column]) }
        .map { |row| change("remove", row[@uuid_column], label.call(row), {}) }
      (seen + removed).map { |change| change.with(values: change.values.as_json) }
    end

    def change(action, key, label, values)
      Plan::Change.new(action: action, key: key, label: label, values: values, target: @model.name)
    end

    # Writes the changes in a few statements however many rows, with the
    # cast values, and marks every row Moss returned as seen. Returns the
    # rows written (Wsjrdp::Sync::Stats); marking as seen does not count.
    def apply(changes, now)
      by_action = changes.group_by(&:action)
      rows = ->(action, extra = {}) { by_action.fetch(action, []).map { |change| @rows.fetch(change.key).merge(extra) } }
      stats = Stats.new
      stats.add("inserted", @model.insert_all!(rows.call("create", "last_seen_at" => now)).length) if by_action["create"]
      stats.add("updated", @model.upsert_all(rows.call("update"), unique_by: @uuid_column).length) if by_action["update"]
      if by_action["restore"]
        stats.add("updated", @model.upsert_all(rows.call("restore", "moss_removed_at" => nil), unique_by: @uuid_column).length)
      end
      if by_action["remove"]
        stats.add("soft_deleted", @model.where(@uuid_column => by_action["remove"].map(&:key))
          .update_all(moss_removed_at: now, updated_at: now))
      end
      @model.where(@uuid_column => @rows.keys).update_all(last_seen_at: now)
      stats
    end

    # How many rows are in Moss now (in the table, not marked removed).
    def current_count = existing.values.count { |row| row.moss_removed_at.nil? }

    private

    def cast(attributes) = attributes.to_h { |column, value| [column, @model.type_for_attribute(column).cast(value)] }
  end
end
