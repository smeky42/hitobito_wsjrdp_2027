# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp::Filtering
  # The "table" of an array-backed dataset: its fields, each with an SQL type
  # and how to read it from a row (doc/wsjrdp/generic_filter_builder.md,
  # "Filtering arrays"). A schema binds to it like to a relation -- its
  # attributes name fields as columns (a symbol, or a lambda over the
  # arel_table returning one or several of them) -- and
  # Wsjrdp::Filtering::ArrayCompiler filters an Array of rows with it.
  #
  #   CHAINS = Wsjrdp::Filtering::ArraySource.define(:registration_chains) do |s|
  #     s.field :person_id, :integer
  #     s.field :key, :text
  #     s.field :state, :text, ->(chain) { chain.state.to_s }
  #   end
  #
  # A field without a reader calls the method of its name on the row. A reader
  # gives the Ruby value of the field's type: Integer/BigDecimal for :integer
  # and :numeric, String for :text, Date for :date, true/false for :boolean,
  # nil for none.
  class ArraySource
    SQL_TYPES = %i[integer bigint numeric text date boolean].freeze
    INDEX = "__index"

    Field = Data.define(:name, :sql_type, :reader)

    attr_reader :name, :fields

    def self.define(name, &block)
      new(name).tap(&block).tap(&:freeze_fields)
    end

    def initialize(name)
      @name = name.to_s
      @fields = {}
    end

    def field(name, sql_type, reader = nil, &block)
      sql_type = sql_type.to_sym
      raise ArgumentError, "field #{name}: unknown SQL type #{sql_type.inspect}" unless SQL_TYPES.include?(sql_type)

      reader ||= block || ->(row) { row.public_send(name) }
      @fields[name.to_sym] = Field.new(name: name.to_sym, sql_type: sql_type, reader: reader)
    end

    def freeze_fields
      @fields.freeze
    end

    # What a schema binds against (Wsjrdp::Filtering::Attribute#resolved_against):
    # a plain Arel table without a model, so no database table is looked up.
    def arel_table = @arel_table ||= Arel::Table.new(@name)

    # A relation-like stand-in for FilterSchema#compile's `relation.merge(schema.base)`.
    def merge(_other) = self

    def fetch(field_name)
      @fields.fetch(field_name.to_sym) do
        raise ArgumentError, "#{@name}: no field #{field_name.inspect}"
      end
    end

    # The field a bound column (an Arel attribute of this source's table)
    # stands for; anything else (an SQL expression) has no field.
    def field_of(column)
      return nil unless column.is_a?(Arel::Attributes::Attribute) && column.relation.name.to_s == @name

      @fields[column.name.to_sym]
    end
  end
end
