# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027::PaperTrail
  # PaperTrail's YAML serializer (versions.object and object_changes), with the
  # decimals of selected attributes written as plain strings ('312.5') instead
  # of "!ruby/object:BigDecimal" tags -- readable by every YAML reader (the
  # scripts in wsjrdp_scripts, SQL, the core's loaders that permit no
  # BigDecimal) without knowing Ruby's types. Loading turns them back into
  # BigDecimal, so changeset and reify see the same values as before.
  #
  # Every other attribute is written exactly as PaperTrail writes it; versions
  # written before keep their tags and still load.
  module YamlSerializer
    extend self

    # The attributes whose decimals are written as strings.
    STRING_DECIMAL_ATTRS = %w[wsjrdp_raw_installments_eur].freeze

    def dump(object)
      object = object.to_hash if object.is_a?(ActiveSupport::HashWithIndifferentAccess)
      if object.is_a?(Hash)
        object = object.to_h do |attr, value|
          [attr, STRING_DECIMAL_ATTRS.include?(attr.to_s) ? decimals_to_strings(value) : value]
        end
      end
      ::PaperTrail::Serializers::YAML.dump(object)
    end

    def load(string)
      object = ::PaperTrail::Serializers::YAML.load(string)
      return object unless object.is_a?(Hash)

      STRING_DECIMAL_ATTRS.each do |attr|
        object[attr] = strings_to_decimals(object[attr]) if object.key?(attr)
      end
      object
    end

    def where_object_condition(...) = ::PaperTrail::Serializers::YAML.where_object_condition(...)

    private

    # BigDecimal#to_s("F"): "2026.0", "312.5", "0.01".
    def decimals_to_strings(value)
      case value
      when BigDecimal then value.to_s("F")
      when Array then value.map { |v| decimals_to_strings(v) }
      else value
      end
    end

    def strings_to_decimals(value)
      case value
      when String then BigDecimal(value)
      when Array then value.map { |v| strings_to_decimals(v) }
      else value
      end
    end
  end
end
