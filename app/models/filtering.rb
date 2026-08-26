# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Generic CNF filter engine (doc/generic_filter_builder.md). A filter is an AND
# of slots; a slot is an OR of conditions; a condition is one atom
# (attribute, operator, operands). This file holds the global operator
# vocabulary and the small value objects; the heavier parts live in
# app/models/filtering/.
#
# The engine is dataset-agnostic: datasets declare a Filtering::Schema
# (attributes over a base relation); everything else -- compiling to Arel, the
# URL codec, the catalog for the generic UI -- is shared.
module Filtering
  # GLOBAL operator vocabulary: key <-> short_key is ONE bijection for the whole
  # system. Technically uniqueness would only be needed within one attribute's
  # operator set (a condition names its attribute first), but the global rule
  # keeps every URL and tree readable without knowing the attribute's type.
  # Adding an operator later = one line here + its per-type implementation(s).
  OPERATOR_VOCABULARY = {
    in: :in,                 # membership ("ist")
    not_in: :ni,             # negated membership ("ist nicht")
    present: :pr,            # IS NOT NULL ("hat Wert")
    blank: :bl,              # IS NULL ("ist leer")
    gte: :ge,                # >=  (decimal, date; date label "ab")
    lt: :lt,                 # <   (date label "vor")
    between: :bt,            # closed range [a, b]
    in_month: :im,           # date within one month ("im Monat", operand YYYY-MM)
    in_year: :iy,            # date within one year ("im Jahr", operand YYYY)
    # Text operators come in case-insensitive (default) / case-sensitive pairs,
    # linked via case_group metadata (the UI shows one entry + a case toggle).
    eq: :eq,                 # exact match, case-insensitive ("ist genau")
    eq_cs: :eqc,             # exact match, case-sensitive
    contains: :ct,           # substring ILIKE ("enthält")
    contains_cs: :ctc,       # substring LIKE
    not_contains: :nct,      # negated substring ILIKE ("enthält nicht")
    not_contains_cs: :ncc,   # negated substring LIKE
    regex: :re,              # POSIX regex ~* ("Regex")
    regex_cs: :rec           # POSIX regex ~
  }.freeze

  raise "OPERATOR_VOCABULARY short_keys are not unique" if
    OPERATOR_VOCABULARY.values.uniq.size != OPERATOR_VOCABULARY.size

  # One atom: attribute + operator (symbols, matching the registry) + operands
  # (raw values from the wire; cast in the compiler).
  Condition = Data.define(:attribute, :operator, :operands)

  # An OR-group of conditions.
  Slot = Data.define(:conditions)
end
