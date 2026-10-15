# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The comfort answers of jamboree_data (Wsjrdp2027::Person::JamboreeData::
# COMFORT_ATTRS) are stored as true and false from now on; before, the form
# stored a ticked box (true = "wohl") and dropped an unticked one. Fills the
# missing ones: nothing answered -- the part was never edited -- all true;
# something answered, the missing ones false (boxes left unticked). Each
# person changed gets a version (mutation_id MUTATION, by WHODUNNIT like
# other changes made for all people, shown as "geändert durch" that person),
# which `down` reads to take the filled keys out again. A person with all
# answers is left as is.
class MigrateJamboreeComfortChoices < ActiveRecord::Migration[7.1]
  COMFORT_ATTRS = %w[
    comfortable_on_water
    comfortable_in_water
    comfortable_without_balance
    comfortable_in_crowd
    comfortable_flashing_lights
    comfortable_loud_noise
    comfortable_confined_space
  ].freeze
  MUTATION = "migration-20261015000100-comfort"
  # Person 1, the administrator account.
  WHODUNNIT = "1"

  def up
    keys = "ARRAY[#{COMFORT_ATTRS.map { |attr| quote(attr) }.join(", ")}]::text[]"
    execute <<~SQL
      WITH filled AS (
        SELECT people.id, people.jamboree_data ?| #{keys} AS answered,
          ARRAY(SELECT key FROM unnest(#{keys}) key WHERE NOT people.jamboree_data ? key) AS missing
        FROM people
        WHERE NOT people.jamboree_data ?& #{keys}
      ), updated AS (
        UPDATE people
        SET jamboree_data = people.jamboree_data ||
          (SELECT jsonb_object_agg(key, NOT filled.answered) FROM unnest(filled.missing) key)
        FROM filled
        WHERE people.id = filled.id
        RETURNING people.id, filled.answered, filled.missing
      )
      INSERT INTO versions (item_type, item_id, event, whodunnit, whodunnit_type, object_changes,
        main_type, main_id, created_at, mutation_id)
      SELECT 'Person', updated.id, 'update', #{quote(WHODUNNIT)}, 'Person',
        E'---\\n' || string_agg(key || E':\\n- \\n- ' || (NOT updated.answered)::text || E'\\n', '' ORDER BY key),
        'Person', updated.id, now(), #{quote(MUTATION)}
      FROM updated, unnest(updated.missing) key
      GROUP BY updated.id, updated.answered
    SQL
  end

  def down
    execute <<~SQL
      UPDATE people
      SET jamboree_data = people.jamboree_data -
        ARRAY(SELECT match[1] FROM regexp_matches(versions.object_changes, '^(comfortable_[a-z_]+):$', 'gn') match)
      FROM versions
      WHERE versions.mutation_id = #{quote(MUTATION)} AND versions.item_type = 'Person'
        AND versions.item_id = people.id
    SQL
    execute "DELETE FROM versions WHERE mutation_id = #{quote(MUTATION)}"
  end

  private

  def quote(value) = connection.quote(value)
end
