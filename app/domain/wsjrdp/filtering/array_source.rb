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
  #
  # :integer_list is a field of SEVERAL values (an Array of Integers, maybe
  # empty; in SQL integer[]), e.g. the accounts of one side of an Umbuchung.
  # A REFERENCE attribute over it matches like one over several columns
  # (Types::REFERENCE): `ist` if any element is one of the values, `ist nicht`
  # if none is (an empty list included), `hat Wert` if the list has an
  # element, `ist leer` if it has none. Its column is a ListAttribute, which
  # answers those predicates with the array operators.
  class ArraySource
    SQL_TYPES = %i[integer bigint numeric text date boolean integer_list].freeze
    LIST_TYPES = {integer_list: "integer[]"}.freeze
    INDEX = "__index"

    Field = Data.define(:name, :sql_type, :reader) do
      def list? = LIST_TYPES.key?(sql_type)

      # The type a value is cast to in the VALUES list.
      def sql_cast = LIST_TYPES.fetch(sql_type, sql_type.to_s)
    end

    # The column of a list field: the predicates the REFERENCE operators ask
    # of a column, over an integer[]. Elements and operands are Integers, so
    # the array literals hold nothing but digits.
    class ListAttribute < Arel::Attributes::Attribute
      def self.literal(values)
        Arel.sql("'{#{values.filter_map { |value| Integer(value.to_s, exception: false) }.join(",")}}'::integer[]")
      end

      # Any element is one of the values (array overlap).
      def in(values) = Arel::Nodes::Grouping.new(Arel::Nodes::InfixOperation.new("&&", self, self.class.literal(values)))

      # No element is one of them; the empty list too.
      def not_in(values) = Arel::Nodes::Not.new(self.in(values))

      def eq(value) = value.nil? ? cardinality.eq(0) : super

      def not_eq(value) = value.nil? ? cardinality.gt(0) : super

      private

      def cardinality = Arel::Nodes::NamedFunction.new("cardinality", [self])
    end

    # The table a schema binds to: a list field's column is a ListAttribute.
    class Table < Arel::Table
      def initialize(name, fields)
        super(name)
        @list_fields = fields
      end

      def [](name, table = self)
        return super unless @list_fields.call.fetch(name.to_sym, nil)&.list?

        ListAttribute.new(table, name.to_s)
      end
    end

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
    def arel_table = @arel_table ||= Table.new(@name, -> { @fields })

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
