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
    def jsonb_accessor(store_attribute, key, prefix: nil, suffix: nil, strip: false, delete_on_blank: true, created_at_key: nil, updated_at_key: nil)
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
          value = value&.strip if strip
          if delete_on_blank && value.blank?
            send(store_attribute)&.delete(accessor_key)
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
      end
    end
  end
end
