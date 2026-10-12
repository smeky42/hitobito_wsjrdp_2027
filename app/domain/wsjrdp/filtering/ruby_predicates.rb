# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp::Filtering
  # The Ruby twin of every operator of Wsjrdp::Filtering::Types, for the :ruby
  # strategy of Wsjrdp::Filtering::ArrayCompiler. Each answers what the SQL of
  # the operator answers, including SQL's NULL rules: a comparison with NULL
  # is not true, so a row without a value fails every comparison, `ist nicht`
  # included; `enthält nicht` counts NULL as the empty text (COALESCE).
  #
  # A predicate gets the row's values (one per column of the attribute; most
  # attributes have one) and the operands as prepared once per condition
  # (prepare). Known differences from PostgreSQL: case-insensitive matching
  # folds with Ruby's downcase (ILIKE folds with the database's lower()), and a
  # regex is a Ruby regex (PostgreSQL's are POSIX) -- the same for the
  # patterns anyone types, different in rare corners.
  module RubyPredicates
    module_function

    # Operands turned into what the predicates compare with: folded terms,
    # regexes, month and year bounds.
    def prepare(type, operator, operands)
      case operator
      when :contains, :not_contains then [operands[0].to_s.downcase]
      when :eq then (type == :text) ? [operands[0].to_s.downcase] : operands
      when :glob then [glob_regex(operands[0], true)]
      when :glob_cs then [glob_regex(operands[0], false)]
      when :regex then [Regexp.new(operands[0], Regexp::IGNORECASE)]
      when :regex_cs then [Regexp.new(operands[0])]
      when :in_month
        first = Date.strptime(operands[0], "%Y-%m")
        [first, first.end_of_month]
      when :in_year then [Date.new(operands[0], 1, 1), Date.new(operands[0], 12, 31)]
      when :in, :not_in then [operands.map(&:to_s).to_set]
      else operands
      end
    end

    # * and ? are the only wildcards; the pattern matches the whole value.
    def glob_regex(term, ignore_case)
      body = term.to_s.chars.map { |char| {"*" => ".*", "?" => "."}[char] || Regexp.escape(char) }.join
      Regexp.new("\\A#{body}\\z", (ignore_case ? Regexp::IGNORECASE : 0) | Regexp::MULTILINE)
    end

    def compare(value, operand, op) = !value.nil? && value.public_send(op, operand)

    def text_any(values, &block) = values.any? { |value| !value.nil? && block.call(value.to_s) }

    COMPARISONS = {
      eq: ->(values, ops) { compare(values[0], ops[0], :==) },
      gte: ->(values, ops) { compare(values[0], ops[0], :>=) },
      gt: ->(values, ops) { compare(values[0], ops[0], :>) },
      lt: ->(values, ops) { compare(values[0], ops[0], :<) },
      lte: ->(values, ops) { compare(values[0], ops[0], :<=) },
      between: ->(values, ops) { compare(values[0], ops[0], :>=) && values[0] <= ops[1] },
      present: ->(values, _ops) { !values[0].nil? },
      blank: ->(values, _ops) { values[0].nil? }
    }.freeze

    TABLE = {
      %i[reference in] => ->(values, ops) { values.any? { |value| !value.nil? && ops[0].include?(value.to_s) } },
      %i[reference not_in] => ->(values, ops) { values.all? { |value| !value.nil? && !ops[0].include?(value.to_s) } },
      %i[reference present] => ->(values, _ops) { values.any? { |value| !value.nil? } },
      %i[reference blank] => ->(values, _ops) { values.all?(&:nil?) },

      %i[decimal nonzero] => ->(values, _ops) { compare(values[0], 0, :!=) },

      %i[date in_month] => ->(values, ops) { compare(values[0], ops[0], :>=) && values[0] <= ops[1] },
      %i[date in_year] => ->(values, ops) { compare(values[0], ops[0], :>=) && values[0] <= ops[1] },

      %i[text contains] => ->(values, ops) { text_any(values) { |text| text.downcase.include?(ops[0]) } },
      %i[text contains_cs] => ->(values, ops) { text_any(values) { |text| text.include?(ops[0]) } },
      %i[text not_contains] => ->(values, ops) { values.none? { |value| value.to_s.downcase.include?(ops[0]) } },
      %i[text not_contains_cs] => ->(values, ops) { values.none? { |value| value.to_s.include?(ops[0]) } },
      %i[text eq] => ->(values, ops) { text_any(values) { |text| text.downcase == ops[0] } },
      %i[text eq_cs] => ->(values, ops) { text_any(values) { |text| text == ops[0] } },
      %i[text glob] => ->(values, ops) { text_any(values) { |text| ops[0].match?(text) } },
      %i[text glob_cs] => ->(values, ops) { text_any(values) { |text| ops[0].match?(text) } },
      %i[text regex] => ->(values, ops) { text_any(values) { |text| ops[0].match?(text) } },
      %i[text regex_cs] => ->(values, ops) { text_any(values) { |text| ops[0].match?(text) } },

      %i[enum in] => ->(values, ops) { !values[0].nil? && ops[0].include?(values[0].to_s) },
      %i[enum not_in] => ->(values, ops) { !values[0].nil? && !ops[0].include?(values[0].to_s) }
    }.merge(
      %i[decimal date].product(COMPARISONS.keys).to_h { |type, op| [[type, op], COMPARISONS.fetch(op)] }
    ).freeze
  end
end
