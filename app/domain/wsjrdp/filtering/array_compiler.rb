# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp::Filtering
  # Filters an Array of rows by a CNF query over a schema bound to a
  # Wsjrdp::Filtering::ArraySource (doc/wsjrdp/generic_filter_builder.md,
  # "Filtering arrays"). Two strategies, the same answer:
  #
  # - :ruby evaluates every condition in Ruby (Ruby). No database; every
  #   operator has a Ruby twin of its SQL meaning (RUBY_PREDICATES). A column
  #   must be a plain field -- an SQL expression has no Ruby twin.
  # - :sql hands the rows to PostgreSQL as a VALUES list and runs the very
  #   predicates the relation-backed tables run (Sql). Exactly the SQL
  #   meaning; costs one query whose text grows with the rows.
  #
  # The strategy comes from the dataset (ArrayFilterSchema#array_strategy),
  # by default from Settings.filtering.array_strategy.
  #
  # Like Wsjrdp::Filtering::Compiler: AND across slots, OR within a slot, and a
  # condition the schema does not know, whose operands do not cast or whose
  # operand count does not fit is dropped (neutral). The rows keep their order.
  module ArrayCompiler
    STRATEGIES = %i[ruby sql].freeze

    module_function

    def for(strategy)
      case strategy.to_s.to_sym
      when :ruby then Ruby
      when :sql then Sql
      else raise ArgumentError, "unknown array filter strategy #{strategy.inspect} (#{STRATEGIES.join(", ")})"
      end
    end

    def default_strategy = (Settings.filtering&.array_strategy.presence || :ruby).to_sym

    def apply(query, rows, schema:, strategy: default_strategy)
      self.for(strategy).new(schema).apply(query, rows)
    end

    # The conditions that survive the neutral checks, per slot, with their
    # cast operands: [[[attribute, operator, operands], ...], ...]. Slots left
    # empty are dropped, as in Compiler.
    def compiled_slots(query, schema)
      query.slots.filter_map do |slot|
        conditions = slot.conditions.filter_map do |condition|
          attribute = schema.find(condition.attribute) or next
          operator = attribute.operator(condition.operator) or next
          cast = operator.cast || attribute.type.method(:cast)
          operands = condition.operands.map { |value| cast.call(value) }
          next if operands.any?(&:nil?) || !operator.arity_satisfied?(operands)

          [attribute, operator, operands]
        end
        conditions.presence
      end
    end

    # Weg A: the conditions in Ruby. Each field is read once per row and
    # only when a condition needs it.
    class Ruby
      def initialize(schema)
        @schema = schema
        @source = schema.base
      end

      def apply(query, rows)
        return rows if query.nil?

        slots = ArrayCompiler.compiled_slots(query, @schema)
        return rows if slots.empty?

        columns = Hash.new { |hash, field| hash[field] = rows.map(&field.reader) }
        indices = (0...rows.size).to_a
        slots.each do |conditions|
          predicates = conditions.map { |attribute, operator, operands| predicate(attribute, operator, operands, columns) }
          indices.select! { |index| predicates.any? { |predicate| predicate.call(index) } }
        end
        indices.map { |index| rows[index] }
      end

      private

      # ->(index) { true/false } for one condition.
      def predicate(attribute, operator, operands, columns)
        fields = Types.wrap(attribute.column).map do |column|
          @source.field_of(column) ||
            raise(ArgumentError, "attribute #{attribute.key}: the :ruby strategy needs plain fields, " \
                                 "not an SQL expression (use :sql)")
        end
        test = RubyPredicates::TABLE.fetch([attribute.type.key, operator.key]) do
          raise ArgumentError, "no Ruby predicate for #{attribute.type.key}/#{operator.key}"
        end
        prepared = RubyPredicates.prepare(attribute.type.key, operator.key, operands)
        value_columns = fields.map { |field| columns[field] }
        ->(index) { test.call(value_columns.pluck(index), prepared) }
      end
    end

    # Weg B: the rows as VALUES, the predicates of the relation-backed tables.
    class Sql
      # What Compiler#apply reduces the predicates into.
      class Predicates
        attr_reader :list

        def initialize = @list = []

        def where(predicate)
          @list << predicate
          self
        end
      end

      def initialize(schema)
        @schema = schema
        @source = schema.base
      end

      def apply(query, rows)
        return rows if query.nil? || rows.empty?

        predicates = Predicates.new
        Compiler.new(@schema).apply(query, relation: predicates)
        return rows if predicates.list.empty?

        manager = Arel::SelectManager.new
        manager.project(Arel.sql("#{quoted_name}.#{connection.quote_column_name(ArraySource::INDEX)}"))
        manager.from(Arel.sql(values_sql(rows, fields_for(query))))
        predicates.list.each { |predicate| manager.where(predicate) }
        connection.select_values(manager.to_sql).map(&:to_i).sort.map { |index| rows[index] }
      end

      # "(VALUES (0, 'a'::text, ...), ...) AS name(__index, field, ...)" -- every
      # value cast to its field's type, so NULLs and the first row type the
      # columns alike.
      def values_sql(rows, fields)
        readers = fields.map { |field| [field.reader, "::#{field.sql_type}"] }
        tuples = rows.each_with_index.map do |row, index|
          "(#{index}#{readers.map { |reader, cast| ", #{quote(reader.call(row))}#{cast}" }.join})"
        end
        names = [ArraySource::INDEX, *fields.map(&:name)].map { |name| connection.quote_column_name(name) }
        "(VALUES #{tuples.join(", ")}) AS #{quoted_name}(#{names.join(", ")})"
      end

      private

      def connection = ActiveRecord::Base.connection

      def quoted_name = connection.quote_table_name(@source.name)

      def quote(value) = value.nil? ? "NULL" : connection.quote(value)

      # The fields the query's attributes name; all of them when one of its
      # columns is an SQL expression (which may read any field).
      def fields_for(query)
        columns = query.slots.flat_map(&:conditions)
          .filter_map { |condition| @schema.find(condition.attribute) }
          .flat_map { |attribute| Types.wrap(attribute.column) }
        fields = columns.map { |column| @source.field_of(column) }
        fields.any?(&:nil?) ? @source.fields.values : fields.uniq
      end
    end
  end
end
