# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Filtering
  # The reusable type library (one place for the whole atom vocabulary).
  # Arel notes: `matches(pattern, nil, false)` renders ILIKE on PostgreSQL
  # (true -> LIKE); `matches_regexp(pattern, cs)` renders ~ / ~*; `or` wraps in
  # grouping parentheses automatically.
  module Types
    LIKE_SPECIALS = /[%_\\]/

    IN_MANY = {label_many: "ist eines von",
               many_hint: "Mehrfachauswahl: es genügt, wenn EINER der Werte zutrifft (ODER)."}.freeze
    NOT_IN_MANY = {label_many: "ist keines von",
                   many_hint: "Mehrfachauswahl: KEINER der Werte darf zutreffen."}.freeze

    def self.escape_like(term)
      term.gsub(LIKE_SPECIALS) { |c| "\\#{c}" }
    end

    # NEVER Array(): a single Arel attribute is a Struct and Array() would
    # explode it into [table, name]. Explicit wrap instead.
    def self.wrap(columns)
      columns.is_a?(Array) ? columns : [columns]
    end

    # COALESCE(col, '') -- makes negated text predicates deterministic on NULL
    # columns (a NULL Belegfeld simply counts as "does not contain").
    def self.coalesce(column)
      Arel::Nodes::NamedFunction.new("COALESCE", [column, Arel::Nodes.build_quoted("")])
    end

    def self.contains_predicate(cols, term, case_sensitive)
      pattern = "%#{escape_like(term)}%"
      wrap(cols).map { |c| c.matches(pattern, nil, case_sensitive) }.reduce(:or)
    end

    def self.not_contains_predicate(cols, term, case_sensitive)
      pattern = "%#{escape_like(term)}%"
      ors = wrap(cols).map { |c| coalesce(c).matches(pattern, nil, case_sensitive) }.reduce(:or)
      Arel::Nodes::Not.new(Arel::Nodes::Grouping.new(ors))
    end

    def self.eq_predicate(cols, term, case_sensitive)
      if case_sensitive
        wrap(cols).map { |c| c.eq(term) }.reduce(:or)
      else
        wrap(cols).map { |c| c.matches(escape_like(term), nil, false) }.reduce(:or)
      end
    end

    def self.regex_predicate(cols, pattern, case_sensitive)
      wrap(cols).map { |c| c.matches_regexp(pattern, case_sensitive) }.reduce(:or)
    end

    # Ruby-side plausibility check for user regexes (drops obvious garbage; PG
    # POSIX syntax differs in rare corners, which then simply match nothing).
    REGEX_CAST = ->(v) {
      s = v.to_s
      begin
        Regexp.new(s)
        s
      rescue RegexpError
        nil
      end
    }

    YEAR_CAST = ->(v) {
      y = Integer(v.to_s.strip, exception: false)
      y&.between?(1900, 2100) ? y : nil
    }

    MONTH_CAST = ->(v) {
      s = v.to_s.strip
      /\A\d{4}-(0[1-9]|1[0-2])\z/.match?(s) ? s : nil
    }

    # Reference attributes may span SEVERAL columns (e.g. "Konto oder
    # Gegenkonto"): `in`/`present` match if ANY column does, `not_in`/`blank`
    # require it of EVERY column. Single-column attributes are unaffected.
    REFERENCE = Type.new(key: :reference, control: "multiselect", operators: [
      Operator.new(key: :in, label: "ist", arity: :many, **IN_MANY) { |c, v|
        Types.wrap(c).map { |col| col.in(v) }.reduce(:or)
      },
      Operator.new(key: :not_in, label: "ist nicht", arity: :many, **NOT_IN_MANY) { |c, v|
        Types.wrap(c).map { |col| col.not_in(v) }.reduce(:and)
      },
      Operator.new(key: :present, label: "hat Wert", arity: :none) { |c, _|
        Types.wrap(c).map { |col| col.not_eq(nil) }.reduce(:or)
      },
      Operator.new(key: :blank, label: "ist leer", arity: :none) { |c, _|
        Types.wrap(c).map { |col| col.eq(nil) }.reduce(:and)
      }
    ])

    DECIMAL = Type.new(key: :decimal, control: "number_range", operators: [
      Operator.new(key: :eq, label: "ist genau", arity: :one) { |c, v| c.eq(v[0]) },
      Operator.new(key: :gte, label: "≥", arity: :one) { |c, v| c.gteq(v[0]) },
      Operator.new(key: :lt, label: "<", arity: :one) { |c, v| c.lt(v[0]) },
      Operator.new(key: :between, label: "im Bereich", arity: :two) { |c, v| c.gteq(v[0]).and(c.lteq(v[1])) },
      Operator.new(key: :present, label: "hat Wert", arity: :none) { |c, _| c.not_eq(nil) },
      Operator.new(key: :blank, label: "ist leer", arity: :none) { |c, _| c.eq(nil) }
    ])

    # Same comparison KEYS as decimal (one global concept), date labels; plus
    # whole-month / whole-year atoms with their own operand controls.
    DATE = Type.new(key: :date, control: "date_range", operators: [
      Operator.new(key: :gte, label: "ab", arity: :one) { |c, v| c.gteq(v[0]) },
      Operator.new(key: :lt, label: "vor", arity: :one) { |c, v| c.lt(v[0]) },
      Operator.new(key: :between, label: "im Bereich", arity: :two) { |c, v| c.gteq(v[0]).and(c.lteq(v[1])) },
      Operator.new(key: :in_month, label: "im Monat", arity: :one,
        operand_control: "month", cast: MONTH_CAST) { |c, v|
        first = Date.strptime(v[0], "%Y-%m")
        c.gteq(first).and(c.lteq(first.end_of_month))
      },
      Operator.new(key: :in_year, label: "im Jahr", arity: :one,
        operand_control: "year", cast: YEAR_CAST) { |c, v|
        c.gteq(Date.new(v[0], 1, 1)).and(c.lteq(Date.new(v[0], 12, 31)))
      },
      Operator.new(key: :present, label: "hat Wert", arity: :none) { |c, _| c.not_eq(nil) },
      Operator.new(key: :blank, label: "ist leer", arity: :none) { |c, _| c.eq(nil) }
    ])

    # `text` can span several columns; positive predicates match in ANY column,
    # `enthält nicht` requires NO column to match (NULL counts as empty there).
    # Operators come in case-insensitive (default) / case-sensitive pairs
    # linked via case_group; the UI shows one entry + a case toggle.
    TEXT = Type.new(key: :text, control: "text", operators: [
      Operator.new(key: :contains, label: "enthält", arity: :one,
        case_group: :contains, case_sensitive: false) { |cols, v| Types.contains_predicate(cols, v[0], false) },
      Operator.new(key: :contains_cs, label: "enthält (Groß/Klein)", arity: :one,
        case_group: :contains, case_sensitive: true) { |cols, v| Types.contains_predicate(cols, v[0], true) },
      Operator.new(key: :not_contains, label: "enthält nicht", arity: :one,
        case_group: :not_contains, case_sensitive: false) { |cols, v| Types.not_contains_predicate(cols, v[0], false) },
      Operator.new(key: :not_contains_cs, label: "enthält nicht (Groß/Klein)", arity: :one,
        case_group: :not_contains, case_sensitive: true) { |cols, v| Types.not_contains_predicate(cols, v[0], true) },
      Operator.new(key: :eq, label: "ist genau", arity: :one,
        case_group: :eq, case_sensitive: false) { |cols, v| Types.eq_predicate(cols, v[0], false) },
      Operator.new(key: :eq_cs, label: "ist genau (Groß/Klein)", arity: :one,
        case_group: :eq, case_sensitive: true) { |cols, v| Types.eq_predicate(cols, v[0], true) },
      Operator.new(key: :regex, label: "Regex", arity: :one,
        case_group: :regex, case_sensitive: false, cast: REGEX_CAST) { |cols, v| Types.regex_predicate(cols, v[0], false) },
      Operator.new(key: :regex_cs, label: "Regex (Groß/Klein)", arity: :one,
        case_group: :regex, case_sensitive: true, cast: REGEX_CAST) { |cols, v| Types.regex_predicate(cols, v[0], true) }
    ])

    ENUM = Type.new(key: :enum, control: "select", operators: [
      Operator.new(key: :in, label: "ist", arity: :many, **IN_MANY) { |c, v| c.in(v) },
      Operator.new(key: :not_in, label: "ist nicht", arity: :many, **NOT_IN_MANY) { |c, v| c.not_in(v) }
    ])
  end
end
