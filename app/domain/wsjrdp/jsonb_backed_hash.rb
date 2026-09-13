# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# A Hash-like facade over a model's jsonb column, declared with
# `jsonb_backed_hash :column` (see WsjrdpJsonbHelper). Per-key writes persist
# IMMEDIATELY (per-key jsonb_set / "- key"); reads are lazy (the column is
# fetched on demand if it was not loaded) and never bump updated_at.
#
# Persistence model:
#   * persisted record -> writes hit the DB at once via UPDATE ... jsonb_set/-;
#     the in-memory attribute is kept in sync and its dirty state is cleared, so
#     a later record.save never rewrites the whole column (no clobber).
#   * new record -> writes are buffered into the in-memory attribute (dirty), so
#     save/create writes them out with the INSERT.
#
# nil deletes the key; false is a real value. Keys are indifferent (to_s), so
# :a and "a" address the same key. clear and the whole-hash setter (column=)
# replace the whole column (not clobber-safe by nature).
#
# Transaction safety (read-through): after a write inside an open transaction the
# in-memory cache is not trusted -- reads go live to the DB until the transaction
# has fully closed, so a rollback can never leave a stale value readable.
module Wsjrdp
  class JsonbBackedHash
    include Enumerable

    attr_reader :record

    def initialize(record, column)
      @record = record
      @column = column.to_sym
    end

    # --- reads ------------------------------------------------------------
    def [](key) = backing[key.to_s]

    def fetch(key, *default, &block) = backing.fetch(key.to_s, *default, &block)

    def key?(key) = backing.key?(key.to_s)
    alias_method :has_key?, :key?
    alias_method :include?, :key?
    alias_method :member?, :key?

    def dig(key, *rest) = backing.dig(key.to_s, *rest)

    def keys = backing.keys

    def values = backing.values

    def each(&block) = backing.each(&block)

    def empty? = backing.empty?

    def size = backing.size
    alias_method :length, :size

    def to_h = backing.dup
    alias_method :to_hash, :to_h

    def as_json(options = nil) = backing.as_json(options)

    def ==(other) = other.respond_to?(:to_h) && to_h == other.to_h

    def inspect = "#<#{self.class.name} #{@column}=#{backing.inspect}>"
    alias_method :to_s, :inspect

    # --- writes (immediate on a persisted record, buffered on a new one) --
    def []=(key, value)
      value.nil? ? delete(key) : set(key.to_s, value)
    end
    alias_method :store, :[]=

    def delete(key)
      k = key.to_s
      old = backing[k]
      remove(k)
      old
    end

    def clear
      replace_all({})
      self
    end

    def merge!(other)
      other.to_h.each { |k, v| self[k] = v }
      self
    end
    alias_method :update, :merge!

    # Whole-column replace (used by the model's `column=` setter). nil -> {}.
    def replace(value)
      replace_all(value.nil? ? {} : value.to_h)
      self
    end

    private

    def set(key, value)
      if @record.new_record?
        buffer { |h| h[key] = value }
      else
        run_update(["#{qcol} = jsonb_set(COALESCE(#{qcol}, '{}'::jsonb), ARRAY[?]::text[], ?::jsonb, true)",
          key, value.to_json])
        sync { |h| h[key] = value }
      end
    end

    def remove(key)
      if @record.new_record?
        buffer { |h| h.delete(key) }
      else
        run_update(["#{qcol} = COALESCE(#{qcol}, '{}'::jsonb) - ?", key])
        sync { |h| h.delete(key) }
      end
    end

    def replace_all(hash)
      normalized = hash.to_h.transform_keys(&:to_s)
      if @record.new_record?
        buffer { |h| h.replace(normalized) }
      else
        run_update(["#{qcol} = ?::jsonb", normalized.to_json])
        sync { |h| h.replace(normalized) }
      end
    end

    # The hash to read from right now.
    def backing
      if @wrote_in_tx
        return live_hash if transaction_open?
        resync_after_transaction
      end
      if @record.new_record? || @record.has_attribute?(@column)
        @record.read_attribute(@column) || {}
      else
        @memo ||= live_hash
      end
    end

    # New record: keep the change in the in-memory attribute (dirty) so
    # save/create writes it with the INSERT.
    def buffer
      h = (@record.read_attribute(@column) || {}).dup
      yield h
      @record.write_attribute(@column, h)
    end

    # Persisted record: mirror the DB write into the in-memory cache without
    # leaving the column dirty (so a later save won't rewrite the whole column).
    def sync
      if @record.has_attribute?(@column)
        h = (@record.read_attribute(@column) || {}).dup
        yield h
        @record.write_attribute(@column, h)
        @record.send(:clear_attribute_changes, [@column.to_s])
      else
        @memo = nil # lazy cache invalid; re-fetched on next read
      end
      @wrote_in_tx = true if transaction_open?
    end

    # Called on the first read after the transaction we wrote in has closed:
    # pull the DB truth (reverted on rollback, kept on commit) into the cache.
    def resync_after_transaction
      value = live_hash
      if @record.has_attribute?(@column)
        @record.write_attribute(@column, value)
        @record.send(:clear_attribute_changes, [@column.to_s])
      else
        @memo = value
      end
      @wrote_in_tx = false
    end

    def live_hash
      @record.class.unscoped.where(@record.class.primary_key => @record.id).pick(@column) || {}
    end

    def run_update(assignment)
      @record.class.unscoped.where(@record.class.primary_key => @record.id).update_all(assignment)
    end

    def transaction_open?
      @record.class.connection.open_transactions.positive?
    end

    def qcol
      @qcol ||= @record.class.connection.quote_column_name(@column)
    end
  end
end
