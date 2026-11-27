# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp::Sync
  # Compares a Moss list with a table keyed by `number` that other imports
  # write too. A record finds its row by `moss_uuid`, else by number, else
  # it is new. A row Moss no longer returns keeps everything but
  # moss_status, which becomes NULL. A record whose UUID and number point
  # at different rows is a conflict and stays out.
  class MasterTable
    # The key of a change: a row's Moss UUID, else its number.
    NUMBER_KEY = "number:"

    # rows: those the UUID and the number point at.
    Conflict = Data.define(:kind, :uuid, :number, :rows)

    # rows: {uuid => attributes}, as the table's columns, "number" included;
    # skipped: UUIDs Moss returned but that are not written, so their rows stay.
    def initialize(model, rows, skipped: [])
      @model = model
      @rows = rows.to_h { |uuid, attributes| [uuid.to_s.downcase, cast(attributes.stringify_keys)] }
      @skipped = skipped.to_set { |uuid| uuid.to_s.downcase }
    end

    def self.key_of(row) = row.moss_uuid&.downcase || "#{NUMBER_KEY}#{row.number}"

    def existing = @existing ||= @model.all.to_a

    def conflicts = matching[:conflicts]

    # The changes; label gives the text shown for attributes or a row.
    def changes(&label)
      created = matching[:created].map { |uuid| change("create", uuid, label.call(@rows[uuid]), @rows[uuid]) }
      updated = matching[:matched].filter_map do |key, (uuid, row)|
        diff = @rows[uuid].filter_map { |column, value| [column, [row[column], value]] unless row[column] == value }.to_h
        change("update", key, label.call(row), diff) if diff.any?
      end
      removed = gone.map { |row| change("remove", self.class.key_of(row), label.call(row), {"moss_status" => [row.moss_status, nil]}) }
      (created + updated + removed).map { |change| change.with(values: change.values.as_json) }
    end

    def change(action, key, label, values)
      Plan::Change.new(action: action, key: key, label: label, values: values, target: @model.name)
    end

    # Returns the rows written.
    def apply(changes, now)
      by_action = changes.group_by(&:action)
      stats = Stats.new
      if by_action["create"]
        stats.add("inserted", @model.insert_all!(by_action["create"].map { |change| @rows.fetch(change.key) }).length)
      end
      Array(by_action["update"]).each do |change|
        uuid, row = matching[:matched].fetch(change.key)
        values = @rows.fetch(uuid).slice(*change.values.keys).merge("updated_at" => now)
        stats.add("updated", @model.where(id: row.id).update_all(values))
      end
      if by_action["remove"]
        keys = by_action["remove"].to_set(&:key)
        ids = existing.select { |row| keys.include?(self.class.key_of(row)) }.map(&:id)
        stats.add("updated", @model.where(id: ids).update_all(moss_status: nil, updated_at: now))
      end
      stats
    end

    # How many rows Moss knows now (moss_status set).
    def current_count = existing.count { |row| !row.moss_status.nil? }

    private

    def matching = @matching ||= match

    def match
      by_uuid = existing.select(&:moss_uuid).index_by { |row| row.moss_uuid.downcase }
      by_number = existing.index_by(&:number)
      twice = @rows.values.pluck("number").tally.select { |_, count| count > 1 }.keys.to_set
      result = {matched: {}, created: [], conflicts: []}
      @rows.each do |uuid, attributes|
        number = attributes["number"]
        row = by_uuid[uuid]
        kind = if twice.include?(number) then :duplicate_number
        elsif row && row.number != number then :uuid_other_number
        elsif row.nil? && by_number[number]&.moss_uuid then :number_other_uuid
        end
        next result[:conflicts] << Conflict.new(kind, uuid, number, [row, by_number[number]].compact.uniq) if kind

        row ||= by_number[number]
        row ? result[:matched][self.class.key_of(row)] = [uuid, row] : result[:created] << uuid
      end
      result
    end

    # Rows Moss knew but no longer returns; rows in a conflict or skipped stay as they are.
    def gone
      kept = matching[:matched].values.to_set(&:last) + conflicts.flat_map(&:rows)
      existing.select do |row|
        !row.moss_status.nil? && !kept.include?(row) && !@skipped.include?(row.moss_uuid&.downcase)
      end
    end

    def cast(attributes) = attributes.to_h { |column, value| [column, @model.type_for_attribute(column).cast(value)] }
  end
end
