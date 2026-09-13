# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module WsjrdpJsonbHelper
  extend ActiveSupport::Concern
  include ActiveRecord::Store

  module ClassMethods
    # cast: :boolean -- values are cast with ActiveModel::Type::Boolean before
    # the blank check, so form params ("1"/"0"/"true"/"false") behave like real
    # booleans. Combined with delete_on_blank (false.blank? is true), clearing
    # a boolean flag REMOVES the key from the JSONB: absent == false == the
    # default. Also defines a `<key>?` predicate.
    def jsonb_accessor(store_attribute, key, prefix: nil, suffix: nil, strip: false, delete_on_blank: true, created_at_key: nil, updated_at_key: nil, cast: nil)
      accessor_prefix =
        case prefix
        when String, Symbol
          "#{prefix}_"
        when TrueClass
          "#{store_attribute}_"
        else
          ""
        end
      accessor_suffix =
        case suffix
        when String, Symbol
          "_#{suffix}"
        when TrueClass
          "_#{store_attribute}"
        else
          ""
        end
      accessor_key = "#{accessor_prefix}#{key}#{accessor_suffix}"
      store_accessor(store_attribute, key, prefix: prefix, suffix: suffix)
      store_accessor_module = instance_method(:"#{accessor_key}=").owner
      store_accessor_module.module_eval do
        define_method(:"#{accessor_key}=") do |value|
          value = ActiveModel::Type::Boolean.new.cast(value) if cast == :boolean
          value = value&.strip if strip
          if delete_on_blank && value.blank?
            # Delete the STORE key, not the accessor name: with prefix/suffix the
            # two differ, and the value was written under `key`. jsonb hashes use
            # string keys, so normalise with to_s.
            send(store_attribute)&.delete(key.to_s)
          else
            if created_at_key.present? || updated_at_key.present?
              old_value = read_store_attribute(store_attribute, key)
              now = Time.zone.now
              if created_at_key.present?
                old_created_at = read_store_attribute(store_attribute, created_at_key)
                write_store_attribute(store_attribute, created_at_key, now) if old_created_at.nil?
              end
              if updated_at_key.present?
                write_store_attribute(store_attribute, updated_at_key, now) if value != old_value
              end
            end
            write_store_attribute(store_attribute, key, value)
          end
        end
        # A boolean key answers true or false, never nil: an absent key is
        # what "false" looks like in the store, and a reader that returned nil
        # for it would render as an empty field instead of "nein". The cast
        # also protects against a value some other path wrote as a string --
        # "0" is false here, where a bare !! would call it true.
        if cast == :boolean
          read_as_boolean = lambda do |record|
            !!ActiveModel::Type::Boolean.new.cast(
              record.send(:read_store_attribute, store_attribute, key)
            )
          end
          define_method(:"#{accessor_key}") { read_as_boolean.call(self) }
          define_method(:"#{accessor_key}?") { read_as_boolean.call(self) }
        end
      end
    end

    # Declares `column` (a jsonb column) as a Hash-like field whose per-key writes
    # persist immediately; see Wsjrdp::JsonbBackedHash. `record.column` returns the
    # facade, `record.column = {..}` replaces the whole column. Declare this BEFORE
    # any jsonb_accessor on the same column, so those accessors route through the
    # facade too (ActiveRecord::Store reads/writes via the public reader).
    def jsonb_backed_hash(column)
      column = column.to_sym
      ivar = :"@_jsonb_backed_hash_#{column}"
      define_method(column) do
        facade = instance_variable_get(ivar)
        # Rebind after a dup/clone (the ivar would point at the original record).
        facade = instance_variable_set(ivar, Wsjrdp::JsonbBackedHash.new(self, column)) unless
          facade&.record.equal?(self)
        facade
      end
      define_method(:"#{column}=") do |value|
        public_send(column).replace(value)
      end
    end
  end
end
