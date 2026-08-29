# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp::Filtering
  # A schema bound to a concrete base relation: what the Compiler, the URL
  # codec and the catalog consume. The catalog is the UI-facing PROJECTION of
  # this schema (descriptive, never authoritative -- everything the client
  # sends back is re-validated against the schema itself).
  class BoundSchema
    attr_reader :base, :attributes # {Symbol => Attribute}, columns resolved

    def initialize(base:, attributes:)
      @base = base
      @attributes = attributes
    end

    def find(key)
      @attributes[key.to_sym]
    end

    # The sign pairs of the attributes this binding actually carries, as
    # Wsjrdp::Filtering::Schema#sign_aliases describes them -- what the table
    # state hands Wsjrdp::Filtering::SlotEquality so a preset on a magnitude
    # recognises the signed twin of a sign-invariant condition.
    def sign_aliases = Schema.sign_aliases(@attributes)

    # The values a filter preset GROUP may name on `attribute_key`: the option
    # values of that attribute, as Strings and in the order the options come in.
    # nil says the attribute is no ground for a group at all -- this binding does
    # not carry it, or it does not accept the `in` operator the members of a
    # group share one slot under. An attribute that accepts `in` without offering
    # options answers the empty Array: it knows no value a member could name.
    #
    # Host-facing (Wsjrdp::TableState::Filter parses a group declaration with
    # it), never user-facing: the values are the DECLARATION's allow-list.
    def preset_group_values(attribute_key)
      attribute = find(attribute_key)
      return nil unless attribute&.operator(:in)

      Array(attribute.options&.pairs).map { |value, _label| value.to_s }
    end

    # Only catalog:true attributes reach the UI; hidden-condition-only ones
    # (e.g. status) are registered but omitted here. No columns, no SQL, no
    # short_keys, no hidden attributes.
    def catalog
      {attributes: @attributes.values.select(&:catalog?).map(&:as_json)}
    end
  end
end
