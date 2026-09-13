# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Drops auto-generated validators for a column, so the wagon can remove or
# re-declare them. Two sources derive validators from the DB schema and get in
# the way here: validates_by_schema (core person.rb) adds a PresenceValidator
# for every NOT NULL column -- wrong for a jsonb column whose {} default is
# blank? -- and i18n_enum adds an InclusionValidator. This strips the named
# kind(s) for one column, from both the _validators registry AND the
# _validate_callbacks chain (validation actually runs off the chain, so both
# have to go, the way the gender removal has always done it by hand).
#
# It removes ALL validators of the given kind on that column, so use it only
# where that is the intent: a column whose sole validator of that kind is the
# auto-generated one, or one you re-declare yourself straight after (as gender
# does with i18n_enum). It must run AFTER the validator was added; inside a
# wagon module's `included` hook -- which runs after the core class body -- that
# always holds.
module WsjrdpSchemaValidationHelper
  extend ActiveSupport::Concern

  # Validation kind -> the ActiveModel validator class it installs. The
  # ActiveRecord subclasses (e.g. ActiveRecord::Validations::PresenceValidator)
  # are matched too, since they descend from these.
  SCHEMA_VALIDATOR_CLASSES = {
    presence: ActiveModel::Validations::PresenceValidator,
    numericality: ActiveModel::Validations::NumericalityValidator,
    length: ActiveModel::Validations::LengthValidator,
    inclusion: ActiveModel::Validations::InclusionValidator
  }.freeze

  module ClassMethods
    # column: the attribute name (Symbol or String).
    # only:   one kind, or an Array of kinds, from SCHEMA_VALIDATOR_CLASSES.
    def remove_schema_validations(column, only:)
      name = column.to_sym
      Array(only).each do |kind|
        klass = SCHEMA_VALIDATOR_CLASSES.fetch(kind) do
          raise ArgumentError, "unknown validation kind #{kind.inspect} " \
            "(known: #{SCHEMA_VALIDATOR_CLASSES.keys.join(", ")})"
        end
        remove_schema_validator(name, klass)
      end
    end

    private

    def remove_schema_validator(name, klass)
      # _validators is keyed by symbol; its bucket holds only this column's
      # validators, so a type match is enough there.
      _validators[name]&.reject! { |v| v.is_a?(klass) }
      # _validate_callbacks is global, so the callback match must be scoped to
      # the attribute. validates_by_schema stores it as a String (it passes
      # column.name), i18n_enum as a Symbol -- normalise both ends.
      _validate_callbacks
        .select { |c| c.filter.is_a?(klass) && c.filter.attributes.map(&:to_sym).include?(name) }
        .each { |c| _validate_callbacks.delete(c) }
    end
  end
end
