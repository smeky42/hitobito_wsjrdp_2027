# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The "Struktur" block of the Moss overview (fin/moss/index): the three levels
# of the Moss data as an indented tree, every row with a bar relative to its
# level's total, and the foreign-currency transactions as a tag that links to
# the kind's tab filtered down to them.
module Fin::MossOverviewHelper
  # The wallet's base currency: every transaction's `currency` column carries
  # it, `currency_original` is the currency the payment was made in.
  BASE_CURRENCY = "EUR"

  # A signed amount for the cards: the sign leads as its own glyph -- a minus
  # muted, a plus in green (money into the wallet) -- so the direction reads
  # before the number; the number itself stays in the running text colour.
  def moss_signed_amount_display(value, currency = "EUR")
    amount = moss_amount_display(value.abs, currency)
    return amount if value.zero?

    sign = value.negative? ? content_tag(:span, "-", class: "text-muted") : content_tag(:span, "+", class: "text-success")
    safe_join([sign, amount])
  end

  # Share of `part` in `total` in percent (0 when there is nothing to share).
  def moss_share_percent(part, total)
    total.positive? ? (part * 100.0 / total) : 0.0
  end

  # The bar of a structure row. Decorative: the percentage next to it carries
  # the value, so it is hidden from assistive technology.
  def moss_share_bar(part, total)
    width = moss_share_percent(part, total).clamp(0, 100).round(1)
    content_tag(:span, content_tag(:i, "", style: "width: #{width}%"), class: "moss-share", "aria-hidden": "true")
  end

  # "32 %", or "20 % der Buchungen" when the level is named.
  def moss_share_text(part, total, of: nil)
    percent = "#{moss_share_percent(part, total).round} %"
    of ? "#{percent} der #{of}" : percent
  end

  # "n in Fremdwährung" as a link to the kind's tab (or the Transaktionen tab)
  # filtered to those transactions; nothing when there are none.
  def moss_foreign_currency_tag(count, kind = nil)
    return if count.zero?

    tab = kind ? moss_kind_tab_label(kind) : t("fin.tabs.transactions")
    link_to "#{count} in Fremdwährung", moss_foreign_currency_path(kind),
      class: "badge rounded-pill moss-fx-tag", title: "#{tab} in Fremdwährung anzeigen"
  end

  # The listing pinned to the transactions paid in another currency: a Rison
  # filter on "Original-Währung ist nicht EUR" in the URL, encoded through the
  # listing's own schema and param name, so a renamed attribute or field letter
  # cannot leave a stale link here. Every transaction carries an original
  # currency, so "not EUR" is exactly the foreign-currency set.
  def moss_foreign_currency_path(kind = nil)
    base = kind ? moss_kind_tab_path(kind) : moss_transactions_path
    query = Wsjrdp::Filtering::Query.parse([[["currency", "not_in", BASE_CURRENCY]]])
    rison = Wsjrdp::Filtering::UrlCodec.encode(query, schema: Fin::MossTransactionsFilterSchema.bound)
    param = Fin::MossTransactionsController::TRANSACTIONS_POLICY.param_name(:filter)
    "#{base}?#{param}=#{Wsjrdp::Filtering::UrlCodec.escape_for_query(rison)}"
  end
end
