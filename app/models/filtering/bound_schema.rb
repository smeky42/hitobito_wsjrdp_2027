# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Filtering
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

    # Only catalog:true attributes reach the UI; hidden-condition-only ones
    # (e.g. status) are registered but omitted here. No columns, no SQL, no
    # short_keys, no hidden attributes.
    def catalog
      {attributes: @attributes.values.select(&:catalog?).map(&:as_json)}
    end
  end
end
