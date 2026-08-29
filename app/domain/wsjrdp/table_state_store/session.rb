# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The general table-state store (D7): one session slot holding
# {store key => {field short => wire value}}.
#
# hitobito's session store is the active_record_store, so this does not hit the
# 4 KB cookie limit -- but every change still costs a session-row write, so the
# resolver only stores values that differ from the table's defaults, and the
# number of keys is BOUNDED: nested tables remember per parent row (D2), so the
# key set would otherwise grow with every opened row. Keys are grouped by
# controller (everything before the "#") and the oldest keys of a group are
# dropped once it exceeds MAX_KEYS_PER_CONTROLLER; a write re-inserts its key,
# so the surviving keys are the recently used ones.
class Wsjrdp::TableStateStore::Session
  SESSION_SLOT = "wsjrdp_table_state"
  MAX_KEYS_PER_CONTROLLER = 50

  def initialize(session, slot: SESSION_SLOT)
    @session = session
    @slot = slot
  end

  def read(key)
    container[key.to_s]
  end

  # Replaces the entry; an empty hash removes it. Writing an unchanged value is
  # skipped -- assigning the session slot alone would already cost a session-row
  # write on every render.
  def write(key, hash)
    key = key.to_s
    data = container
    value = hash.presence&.to_h { |field, wire| [field.to_s, wire.to_s] }
    return if data[key] == value
    data.delete(key) # re-insert, so insertion order == recency
    data[key] = value if value
    @session[@slot] = evict(data, key)
  end

  def delete(key)
    data = container
    return unless data.key?(key.to_s)
    data.delete(key.to_s)
    @session[@slot] = data
  end

  # Forgets every table whose key starts with `key_prefix` -- one page, or a
  # whole controller.
  def delete_all(key_prefix)
    data = container
    matching = data.keys.select { |key| key.start_with?(key_prefix.to_s) }
    return if matching.empty?
    matching.each { |key| data.delete(key) }
    @session[@slot] = data
  end

  private

  def container
    (@session[@slot] || {}).to_h { |key, value| [key.to_s, value.to_h { |k, v| [k.to_s, v.to_s] }] }
  end

  def evict(data, key)
    group = controller_group(key)
    keys = data.keys.select { |other| controller_group(other) == group }
    (keys.size - MAX_KEYS_PER_CONTROLLER).times { |i| data.delete(keys[i]) }
    data
  end

  def controller_group(key) = key.to_s.split("#").first.to_s
end
