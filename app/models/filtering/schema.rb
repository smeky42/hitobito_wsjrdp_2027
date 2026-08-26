# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Filtering
  # The attribute registry TEMPLATE: declared without a base relation (columns
  # as symbols/lambdas), bound to a concrete relation with #bind -- possibly
  # per request. #derive refines a template into a new one (copy-on-derive;
  # the parent stays untouched). `Schema.define(base: ...)` is sugar for
  # declare + bind in one go. See doc/generic_filter_builder.md §2.2.
  class Schema
    def self.define(base: nil, &block)
      template = new.tap(&block)
      base ? template.bind(base) : template
    end

    def initialize(attributes = {})
      @attributes = attributes
    end

    # Attribute keys and short_keys must be unique WITHIN the schema;
    # re-declaring an existing key replaces it (that is how derive overrides).
    def attribute(key:, **opts)
      a = Attribute.new(key: key, **opts)
      taken = @attributes.values.find { |o| o.key != a.key && o.short_key == a.short_key }
      raise ArgumentError, "short_key #{a.short_key} already taken by #{taken.key}" if taken

      @attributes[a.key] = a
    end

    # --- derivation (server-side refinement; parent untouched) ---------------

    def derive(&block)
      self.class.new(@attributes.dup).tap(&block)
    end

    def remove(*keys)
      keys.each { |k| @attributes.delete(k.to_sym) }
    end

    # Replace an inherited attribute's operator list (narrow OR extend; keys
    # are resolved against the type's implementations, unknown keys raise).
    def operators(key, operator_keys)
      @attributes[key.to_sym] = @attributes.fetch(key.to_sym).with_operators(operator_keys)
    end

    # --- binding --------------------------------------------------------------

    # Template + concrete relation -> BoundSchema (columns resolved). `only:`
    # applies the template partially (just the named attributes); `except:`
    # drops the named ones -- the host's way to make attributes unavailable
    # on a specific page without deriving a named variant.
    def bind(base, only: nil, except: nil)
      attrs = only ? @attributes.slice(*only.map(&:to_sym)) : @attributes
      attrs = attrs.except(*except.map(&:to_sym)) if except
      BoundSchema.new(base: base,
        attributes: attrs.transform_values { |a| a.resolved_against(base) })
    end
  end
end
