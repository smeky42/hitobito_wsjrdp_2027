# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The log entries of the wagon (doc/wsjrdp/log_entries.md): versions.wsjrdp_data
# holds the data of a wsjrdp_* event, versions.additional_info metadata of any
# entry; a GIN index serves queries with @>. The tag entries written so far
# keep their data only as YAML in object_changes ({"tag" => [old, new]}); they
# get it in wsjrdp_data as well ({"tag_name" => name}). The mapping is the one
# of the time of this migration, on purpose not Wsjrdp::LogEvents.
class AddWsjrdpDataToVersions < ActiveRecord::Migration[7.1]
  # The name of a tag in a tag entry's object_changes, by event.
  TAG_NAME_INDEX = {"wsjrdp_add_tag" => 1, "wsjrdp_remove_tag" => 0}.freeze
  BATCH_SIZE = 1000

  def change
    add_column :versions, :wsjrdp_data, :jsonb, null: false, default: {}
    add_column :versions, :additional_info, :jsonb, null: false, default: {}
    add_index :versions, :wsjrdp_data, using: :gin, opclass: :jsonb_path_ops,
      name: "index_versions_on_wsjrdp_data"

    reversible do |dir|
      dir.up { backfill_tag_data }
    end
  end

  # Fills wsjrdp_data of the tag entries that have none from their
  # object_changes. An entry whose object_changes cannot be read keeps {}; the
  # log shows it from object_changes as before. Returns [filled, unreadable].
  def backfill_tag_data
    filled = unreadable = 0
    each_tag_entry_batch do |rows|
      rows.each do |id, event, object_changes|
        tag_name = tag_name_of(event, object_changes)
        if tag_name.nil?
          unreadable += 1
          next
        end

        execute("UPDATE versions SET wsjrdp_data = #{connection.quote({"tag_name" => tag_name}.to_json)}::jsonb " \
                "WHERE id = #{Integer(id)}")
        filled += 1
      end
    end
    say "tag entries: #{filled} filled, #{unreadable} not readable"
    [filled, unreadable]
  end

  private

  def each_tag_entry_batch
    last_id = 0
    loop do
      rows = select_rows(<<~SQL.squish)
        SELECT id, event, object_changes FROM versions
        WHERE event IN (#{TAG_NAME_INDEX.keys.map { |event| connection.quote(event) }.join(", ")})
          AND wsjrdp_data = '{}'::jsonb AND id > #{Integer(last_id)}
        ORDER BY id LIMIT #{BATCH_SIZE}
      SQL
      break if rows.empty?

      yield rows
      last_id = rows.last.first
    end
  end

  def tag_name_of(event, object_changes)
    changes = YAML.safe_load(object_changes.to_s, permitted_classes: [Date, Time, Symbol])
    name = (changes.is_a?(Hash) && changes["tag"].is_a?(Array)) ? changes["tag"][TAG_NAME_INDEX.fetch(event)] : nil
    name.is_a?(String) ? name : nil
  rescue Psych::Exception
    nil
  end
end
