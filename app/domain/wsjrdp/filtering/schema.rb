# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp::Filtering
  # The attribute registry TEMPLATE: declared without a base relation (columns
  # as symbols/lambdas), bound to a concrete relation with #bind -- possibly
  # per request. #derive refines a template into a new one (copy-on-derive;
  # the parent stays untouched). `Schema.define(base: ...)` is sugar for
  # declare + bind in one go. See doc/wsjrdp/generic_filter_builder.md §2.2.
  class Schema
    def self.define(base: nil, &block)
      template = new.tap(&block)
      template.validate_variant_signs!
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

    # A variant group either knows nothing of signs, or it is exactly a sign
    # PAIR: one :signed member and one :absolute one, which is what the editor
    # renders as the ± / |x| toggle. Anything else is a declaration mistake
    # (a forgotten twin, a copied `sign:`) and fails loud, like the operator
    # and short_key checks. Run by Schema.define over the finished declaration
    # -- a group is only complete once its last member is declared. `bind`
    # (except:) may well leave one member behind on a page; that is a display
    # decision, not a declaration, and the editor falls back to the dropdown.
    def validate_variant_signs!
      @attributes.values.group_by(&:variant_group).each do |group, members|
        next if group.nil?

        signs = members.map(&:sign)
        next if signs.all?(&:nil?)

        next if signs.size == 2 && signs.compact.sort == %i[absolute signed]

        raise ArgumentError, "variant group #{group.inspect}: sign must be declared on " \
                             "exactly two members, one :signed and one :absolute " \
                             "(got #{signs.inspect})"
      end
    end

    # The sign PAIRS of a set of attributes as an alias map, {signed key =>
    # absolute key}, both Strings: what Wsjrdp::Filtering::SlotEquality compares
    # a sign-invariant condition (`≠ 0`, `hat Wert`, `ist leer`, `= 0`) by, so
    # `Saldo ≠ 0` and `|Saldo| ≠ 0` are the same condition and a preset on one
    # of them recognises the other. A group missing one of its two members --
    # `bind(except:)` may leave one behind on a page -- contributes nothing.
    def self.sign_aliases(attributes)
      attributes.values.group_by(&:variant_group).each_with_object({}) do |(group, members), map|
        next if group.nil?

        signed = members.find { |member| member.sign == :signed }
        absolute = members.find { |member| member.sign == :absolute }
        map[signed.key.to_s] = absolute.key.to_s if signed && absolute
      end
    end

    def sign_aliases = self.class.sign_aliases(@attributes)

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
