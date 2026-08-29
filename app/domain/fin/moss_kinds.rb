# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The VISUAL half of the Moss kind vocabulary: one icon and one CSS class per
# kind (STI type of moss_transactions). The WORDS live in the locale
# (fin.moss.kinds for tabs and tiles, fin.moss.kind_chips for the chip,
# fin.moss.kind_hints for its tooltip), the ORDER in
# Fin::MossTransactionsFilterSchema::KINDS.
#
# Why a module of its own: the same kind is marked in five places -- the chip
# in the wallet list, the coloured rail of its row, the tiles of /fin/moss, the
# kind tabs and the kind buttons of a filter's "Schnellauswahl"
# (#preset_group, shared by the wallet and the transactions list). Without a
# single source each view
# would pick its own icon, and a fifth kind would have to be hunted down five
# times. Views never see this module directly; they go through
# Fin::MossTransactionsHelper (moss_kind_chip and friends).
#
# The class carries the SLUG of the generated column
# moss_transactions.expense_type (card_transaction, invoice, reimbursement,
# top_up), not the STI type: it is the same discriminator, but lower_snake and
# therefore usable in a class name -- and a row that already knows its
# expense_type can build the class without a lookup.
#
# COLOURS are deliberately absent: they belong to the stylesheet
# (shared/wsjrdp/_moss_kind_styles), which paints them through the CSS class,
# so no colour value is ever duplicated into Ruby.
module Fin::MossKinds
  # Prefix of every kind class, single-sourced so #slug can undo it.
  CSS_PREFIX = "moss-kind-"

  # type => {icon: FontAwesome 5 free SOLID name, css_class:}. The keys are
  # exactly Fin::MossTransactionsFilterSchema::KINDS, in that order (asserted
  # in the spec -- naming the constant here would pull the whole filter schema
  # into every request that only wants an icon).
  STYLE = {
    "MossCardTransaction" => {icon: "credit-card", css_class: "#{CSS_PREFIX}card_transaction"},
    "MossReimbursement" => {icon: "hand-holding-usd", css_class: "#{CSS_PREFIX}reimbursement"},
    "MossInvoice" => {icon: "file-invoice", css_class: "#{CSS_PREFIX}invoice"},
    "MossTopUp" => {icon: "piggy-bank", css_class: "#{CSS_PREFIX}top_up"}
  }.freeze

  class << self
    # FontAwesome 5 solid icon name of a kind, e.g. "credit-card" for
    # <i class="fas fa-credit-card">.
    def icon(type) = entry(type).fetch(:icon)

    # The kind's CSS class, e.g. "moss-kind-card_transaction".
    def css_class(type) = entry(type).fetch(:css_class)

    # The kind's expense_type slug, e.g. "card_transaction".
    def slug(type) = css_class(type).delete_prefix(CSS_PREFIX)

    # The "Schnellauswahl" of the Moss kinds for a table whose filter offers
    # the Art attribute under the key `kind`: ONE declaration
    # (doc/wsjrdp/expandable_table.md, "Presets") the wallet statement and the
    # transactions list share, so a kind is worded, marked and ordered the same
    # wherever it can be picked.
    #
    # The four are one GROUP, not four presets of their own: the kinds are
    # alternatives of the same question, so they share ONE slot `kind in (…)`
    # and two pressed buttons WIDEN the list to both kinds instead of ANDing
    # two slots into nothing. The words are the chip words of the rows
    # (fin.moss.kind_chips), so a button and an "Art" cell read alike; the key
    # is the kind's slug, the value the STI type the filter compares.
    #
    # A METHOD, not a constant: the labels are I18n and must not be looked up
    # while a class loads -- and the KINDS order is read here, when the bar is
    # built, so the filter schema stays out of a request that only wants an
    # icon.
    def preset_group
      {group: "kind", attribute: "kind", operator: "in",
       members: Fin::MossTransactionsFilterSchema::KINDS.map do |kind|
         {key: slug(kind), label: I18n.t("fin.moss.kind_chips.#{kind}"), value: kind,
          icon: icon(kind), css_class: css_class(kind)}
       end}
    end

    private

    # Unknown types raise KeyError on purpose: a new STI subclass must be given
    # its marking here rather than rendering as an unmarked, colourless row
    # that silently looks like "no kind".
    def entry(type) = STYLE.fetch(type.to_s)
  end
end
