# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Reusable helpers for listing DatevBookings: the per-cell formatting and the
# rendering of the column descriptions (Fin::DatevBookingsColumns) as the shared
# `shared/wsjrdp/_expandable_table` column configs. What a column IS -- its
# label, width, wire token, sort expression and whether it is shown by default --
# lives in Fin::DatevBookingsColumns, not here.
module Fin::BookingsHelper
  # Action (eye / delete-marker) column width, in rem.
  ACTION_COLUMN_REM = 2.75

  # The bookings columns as the generic shared/_expandable_table column configs:
  # the descriptions of Fin::DatevBookingsColumns plus this page's cell
  # rendering. `condensed` bakes the compact cell formatting used inside a
  # detail view (the abbreviated headers come from the descriptions themselves).
  def booking_table_columns(condensed: false)
    Fin::DatevBookingsColumns::COLUMNS.map do |col|
      col.to_table_column(cell: ->(booking) { booking_cell(booking, col.key, condensed: condensed) })
    end
  end

  # The summary line above the FULL bookings table: how many bookings the filter
  # leaves, what they add up to, and how much of that counts against a unit's
  # budget. All three figures come from the SAME filtered relation -- the share
  # is the rows object's #subtotal over the one SQL definition of the rule
  # (doc/fin/unit_budget.md) -- so a line can never state a share of a set other
  # than the sum beside it. Every host of the full table hands the rows
  # DatevBooking.with_unit_budget, which is what carries the account joins the
  # expression names.
  def booking_table_summary(rows)
    line = "#{rows.total_count} Buchungen · Summe (gefiltert): #{fin_money(rows.total_sum)}"
    count, sum = rows.subtotal(DatevBooking::EFFECTIVE_IS_UNIT_BUDGET_SQL)
    return line if count.nil?

    "#{line} · davon Unit-Budget: #{fin_money(sum)} (#{count} Buchungen)"
  end

  # number => compact display label, loaded once per request. Accounts use their
  # short_name (falling back to the full name); suppliers (the 700xxx personal
  # accounts) use their name. Account and supplier number ranges are disjoint, so
  # a single number->label lookup unambiguously covers both -- there is no need to
  # store, on the booking, whether a number is an account or a supplier.
  def datev_account_names
    @datev_account_names ||= datev_account_label_map(short: true)
  end

  # number => full (long) name, for overviews where space allows the long form.
  def datev_account_full_names
    @datev_account_full_names ||= datev_account_label_map(short: false)
  end

  # Merged account + supplier label map. `short` picks the account short_name
  # (falling back to the full name) vs. always the full name. Ledger accounts and
  # suppliers use disjoint number ranges (6-digit 7xxxxx creditors live only in
  # wsjrdp_personal_accounts, enforced by CHECK), so the merge simply unions the two name
  # sources; suppliers are merged last so a supplier name still wins should the
  # ranges ever overlap.
  def datev_account_label_map(short:)
    accounts = WsjrdpLedgerAccount.pluck(:number, :short_name, :name).to_h do |number, short_name, name|
      [number, short ? (short_name.presence || name) : name]
    end
    accounts.merge(WsjrdpPersonalAccount.pluck(:number, :name).to_h)
  end

  # Formatted cell value for a booking and a column key. The condensed (in-detail)
  # table shows the bare code for account / cost-center / supplier columns.
  def booking_cell(booking, key, condensed: false)
    case key
    when "signed_base_amount"
      booking_amount_with_currency(booking)
    when "booking_date", "service_date"
      fin_date(booking.public_send(key))
    when "primanota_period"
      booking.primanota_period&.strftime("%Y-%m")
    when "account_number", "offsetting_account_number"
      datev_code_cell(booking.public_send(key), datev_account_names, condensed: condensed)
    when "cost_center_number", "secondary_cost_center_number"
      datev_code_cell(booking.public_send(key), datev_cost_center_names, condensed: condensed)
    when "unit_budget"
      booking_unit_budget_cell(booking, condensed: condensed)
    else
      booking.public_send(key)
    end
  end

  # Amount with the symbol of its currency (Fin::MoneyHelper).
  # `signed_base_amount` is the signed base-currency (EUR) value (incoming +, outgoing -).
  def booking_amount_with_currency(booking)
    # A legs-backed row (account/supplier detail) carries `signed_leg_amount` --
    # the value from THAT account's own perspective; a plain row has only
    # `signed_base_amount`.
    amount = if booking.has_attribute?(:signed_leg_amount)
      booking.signed_leg_amount
    else
      booking.signed_base_amount
    end
    primary = fin_money(amount, booking.base_currency)
    return primary if primary.blank?
    # Foreign-currency booking: base (EUR) amount on the first line, the as-booked
    # SIGNED transaction amount + currency muted on a second line -- only when the
    # transaction currency actually differs from the base currency.
    return primary unless booking_foreign_currency?(booking)
    tx = booking_amount_currency_str(booking.signed_transaction_amount, booking.transaction_currency)
    safe_join([primary, content_tag(:div, tx, class: "text-muted small")])
  end

  # True when the booking was made in a currency other than the base (EUR).
  def booking_foreign_currency?(booking)
    booking.transaction_currency != booking.base_currency
  end

  # A booking figure in the money format of the Finanzen lists: "123,40 €" /
  # "-2.700,00 zł", or nil if blank.
  def booking_amount_currency_str(amount, currency) = fin_money(amount, currency)

  # Human label for a DATEV "Kontenart" code (BANK, EXPENSE, ...). Falls back to
  # the raw code stored in the DB when no translation exists.
  def account_kind_label(code)
    return nil if code.blank?
    I18n.t("fin.account_kind.#{code}", default: code)
  end

  # Translated status ("active"/"deactivated"/...); falls back to the code.
  def fin_status_label(status)
    return nil if status.blank?
    I18n.t("fin.status.#{status}", default: status.humanize)
  end

  # German label for the canonical English debit_credit code: "D" -> "S",
  # "C" -> "H"; falls back to the raw code.
  def debit_credit_label(code)
    return nil if code.blank?
    I18n.t("fin.debit_credit.#{code}", default: code)
  end

  # The same code written OUT ("Soll" / "Haben"), for the booking detail's
  # Betrag row -- everywhere else the short S/H of #debit_credit_label stands.
  def debit_credit_long_label(code)
    return nil if code.blank?
    I18n.t("fin.debit_credit_long.#{code}", default: code)
  end

  # --- Unit-Budget (the resolved answer, DatevBooking#unit_budget) ------------

  # The Unit-Budget cell: "ja" / "nein", with WHERE the answer comes from muted
  # beside it -- and the answer alone where the two accounts simply agreed, the
  # ordinary case that names no source (#unit_budget_source_label). The
  # condensed (in-detail) table shows the answer alone throughout.
  def booking_unit_budget_cell(booking, condensed: false)
    value, source = booking.unit_budget
    answer = unit_budget_answer(value)
    return answer if condensed

    origin = unit_budget_source_label(booking, source)
    return answer if origin.blank?

    safe_join([answer, content_tag(:span, origin, class: "text-muted small")], " ")
  end

  def unit_budget_answer(value) = value ? "ja" : "nein"

  # The source of an answer, named with the number it was read on:
  # "Kostenstelle 9500" (the cost center is not a unit's own and settled it
  # before the accounts were asked), "Konto 66500" / "Gegenkonto 1200" (that one
  # side), "Standard" (no number named an account) -- and "Buchung" for the flag
  # stored on the booking itself.
  #
  # `konten` -- both accounts known and agreeing -- is the ORDINARY case and has
  # no label: naming both numbers would be the longest text on the page for the
  # answer that says the least, so the field stops at "automatisch" and the cell
  # at the bare "ja" / "nein". A source worth reading is one that singles a side
  # out or names the booking itself.
  def unit_budget_source_label(booking, source)
    case source
    when DatevBooking::UNIT_BUDGET_SOURCE_BOOKING then "Buchung"
    when DatevBooking::UNIT_BUDGET_SOURCE_COST_CENTER
      "Kostenstelle #{booking.cost_center_number}"
    when DatevBooking::UNIT_BUDGET_SOURCE_KONTO then "Konto #{booking.account_number}"
    when DatevBooking::UNIT_BUDGET_SOURCE_GEGENKONTO
      "Gegenkonto #{booking.offsetting_account_number}"
    when DatevBooking::UNIT_BUDGET_SOURCE_DEFAULT then "Standard"
    end
  end

  # A code (account / cost center) followed by its name in muted font
  # (name omitted if unknown). The condensed table shows the bare code only.
  def datev_code_cell(code, names, condensed: false)
    return nil if code.blank?
    return code if condensed
    name = names[code]
    return code if name.blank?
    safe_join([code, content_tag(:span, name, class: "text-muted")], " ")
  end

  # number => name, loaded once per request.
  def datev_cost_center_names
    @datev_cost_center_names ||= WsjrdpCostCenter.pluck(:number, :name).to_h
  end

  # The booking detail grid, as explicit rows of cells. Each cell is
  # [label, value], [label, value, span] or [label, value, span, align] (span
  # defaults to 1, span 2 = double-width; align :end right-aligns the value). A
  # nil label renders an empty placeholder cell. Values may be HTML (account /
  # cost-center cells) or plain; blanks -> "—" in the view.
  def booking_detail_field_rows(booking)
    rows = [
      [
        ["Buchungsdatum", fin_date(booking.booking_date)],
        ["Leistungsdatum", fin_date(booking.service_date)],
        ["Beschreibung", booking.posting_text, 2]
      ],
      [
        ["Betrag", booking_amount_currency_str(booking.base_amount, booking.base_currency), 1, :end],
        ["S/H", debit_credit_label(booking.debit_credit)],
        ["Konto", booking_account_cell(booking.account_number, booking.account_kind)],
        ["Gegenkonto", booking_account_cell(booking.offsetting_account_number, booking.offsetting_account_kind)]
      ]
    ]
    # Foreign-currency booking (special case): the as-booked transaction figures,
    # placed directly below the Betrag row so they sit close to it. The
    # Transaktionsbetrag is sign-less, matching the sign-less Betrag above.
    if booking_foreign_currency?(booking)
      rows << [
        ["Transaktionsbetrag",
          booking_amount_currency_str(booking.transaction_amount, booking.transaction_currency), 1, :end],
        ["Wechselkurs", booking_fx_rate_display(booking.exchange_rate)],
        [nil, nil],
        [nil, nil]
      ]
    end
    rows.push(
      [
        ["Kostenstelle", datev_code_cell(booking.cost_center_number, datev_cost_center_names)],
        ["Sekundäre Kostenstelle", datev_code_cell(booking.secondary_cost_center_number, datev_cost_center_names)],
        ["Sphäre", booking.sphere_number],
        [nil, nil]
      ],
      [
        ["Belegfeld 1", booking.document_field_1],
        ["Belegfeld 2", booking.document_field_2],
        ["Buchungs-GUID", booking.buchungs_guid, 2]
      ]
    )
    rows
  end

  # "Betrag / S/H" cell: the sign-less base-currency amount with the S/H flag
  # appended, e.g. "123,40 € S" or "0,73 € H". Used in the compact
  # reconciliation autocomplete labels.
  def booking_base_amount_with_sh(booking)
    [fin_money(booking.base_amount, booking.base_currency), debit_credit_label(booking.debit_credit)]
      .compact.join(" ").presence
  end

  # An exchange rate formatted with up to 6 decimals, German separators.
  def booking_fx_rate_display(rate)
    return if rate.blank?

    number_with_precision(rate, precision: 6, strip_insignificant_zeros: true,
      separator: ",", delimiter: ".")
  end

  # Raw DATEV fields shown (monospace) at the bottom of the booking detail. The
  # "original" account numbers are shown only when they differ from the mapped
  # value (the import remaps some accounts), and the original posting text only
  # when it differs from the posting_text. Blank values are dropped by the view.
  def booking_raw_fields(booking)
    fields = [
      ["Herkunft (HK)", booking.origin_indicator],
      ["Primanota", booking.primanota_number],
      ["KOST1", booking.original_kost1],
      ["KOST2", booking.original_kost2]
    ]
    if booking.original_account_number.present? &&
        booking.original_account_number != booking.account_number
      fields << ["Orig. Konto", booking.original_account_number]
    end
    if booking.original_offsetting_account_number.present? &&
        booking.original_offsetting_account_number != booking.offsetting_account_number
      fields << ["Orig. Gegenkonto", booking.original_offsetting_account_number]
    end
    if booking.original_posting_text.present? &&
        booking.original_posting_text != booking.posting_text
      fields << ["Buchungstext (Original)", booking.original_posting_text]
    end
    # Beleginfo / Zusatzinformation are surfaced as if the original DTVF columns
    # had been kept verbatim: one line per Art and one per Inhalt, under their
    # full DATEV header names (note DATEV's own spelling: "Zusatzinformation-
    # Inhalt" has no space before the dash). Only populated slots exist.
    fields.concat(booking_dtvf_info_rows(booking.beleginfo,
      "Beleginfo - Art", "Beleginfo - Inhalt"))
    fields.concat(booking_dtvf_info_rows(booking.zusatzinformation,
      "Zusatzinformation - Art", "Zusatzinformation- Inhalt"))
    # Any DTVF record field carried over without a dedicated column
    # (raw Beleglink, Festschreibung, Kurs, ...). Stored verbatim in the
    # other_datev_columns JSONB; surfaced here so nothing from the export is hidden.
    booking.other_datev_columns.each do |name, value|
      fields << [name, value]
    end
    fields
  end

  # Expand a beleginfo / zusatzinformation JSONB array ([{num,key,value}]) into
  # the original DTVF column-name rows: for each slot an "<art_prefix> N" row
  # (the Art) and an "<inhalt_prefix> N" row (the Inhalt). Blank values are
  # dropped by the view.
  def booking_dtvf_info_rows(slots, art_prefix, inhalt_prefix)
    Array(slots).flat_map do |slot|
      n = slot["num"]
      [["#{art_prefix} #{n}", slot["key"]], ["#{inhalt_prefix} #{n}", slot["value"]]]
    end
  end

  # A "Konto" / "Gegenkonto" cell: the number + name, with the translated account
  # type (Kontenart) appended in muted parentheses, e.g. "36100 Kreditkarte
  # (Verrechnung)". The type suffix is dropped when unknown.
  def booking_account_cell(number, account_kind)
    cell = datev_code_cell(number, datev_account_names)
    return cell if cell.blank?
    type = account_kind_label(account_kind)
    return cell if type.blank?
    safe_join([cell, content_tag(:span, "(#{type})", class: "text-muted")], " ")
  end

  # --- Match rating (shared with fin/reconciliation/participant_fees) --------

  # Per-tier chip appearance (see Fin::DatevBookingMatcher::Match#tier and
  # doc/fin/recon_linking.md). Four visually distinct colours: :automatic a firm
  # green with a LOCK icon (a deterministic, import-equivalent link);
  # :heuristic_high a green CLOSE to it; :heuristic_middle amber; :heuristic_low
  # orange/red. The heuristic tiers carry the LINK icon (a derived, not locked,
  # match).
  MATCH_TIER_STYLES = {
    automatic: {colour: "#146c43", icon: :lock},
    heuristic_high: {colour: "#2f9e44", icon: :link},
    heuristic_middle: {colour: "#b8860b", icon: :link},
    heuristic_low: {colour: "#d9480f", icon: :link}
  }.freeze

  # The match-rating chip: the tier's icon + score %, coloured per tier
  # (MATCH_TIER_STYLES), an optional target label, and the short basis; the full
  # explanation is the hover title. Shared by the reconciliation page and the
  # booking detail so an explicit link is rated with the same look.
  # compact: shrink the label/basis to `.small` (the dense reconciliation table).
  # Pass compact: false to render them at normal size (the booking detail).
  def match_rating_chip(match, target_label: nil, compact: true)
    return if match.nil?

    style = match_tier_style(match)
    rating = content_tag(:span, style: "color: #{style[:colour]}") do
      safe_join([icon(style[:icon]), content_tag(:span, "#{match.score} %", class: "fw-semibold")], " ")
    end
    size = compact ? "small " : ""
    parts = [rating]
    parts << content_tag(:span, target_label, class: "#{size}ms-1") if target_label.present?
    parts << content_tag(:span, match.basis, class: "#{size}text-muted ms-1") if match.basis.present?
    content_tag(:span, safe_join(parts, " "), title: match.details)
  end

  # A match's chip style ({colour:, icon:}) for its tier -- shared by the chip
  # and the reconciliation candidate lists so their inline mini-chips stay in
  # step with match_rating_chip. Unknown tier falls back to the low style.
  def match_tier_style(match)
    match_tier_style_for(match.tier)
  end

  # Chip style ({colour:, icon:}) for a tier SYMBOL directly -- the quick-select
  # buttons and the legend colour by tier without a Match in hand.
  def match_tier_style_for(tier)
    MATCH_TIER_STYLES[tier] || MATCH_TIER_STYLES[:heuristic_low]
  end

  # The colour/icon legend for the rating chip (all four tiers), built from
  # MATCH_TIER_STYLES so it can never drift from the chips themselves.
  def match_rating_legend
    entries = [
      [:automatic, "automatisch (Import-Regel, 100 %)"],
      [:heuristic_high, "heuristisch 100 %"],
      [:heuristic_middle, "heuristisch über 50 %"],
      [:heuristic_low, "heuristisch bis 50 %"]
    ]
    parts = entries.map do |tier, label|
      style = match_tier_style_for(tier)
      safe_join([content_tag(:span, icon(style[:icon]), style: "color: #{style[:colour]}"), " = #{label}"])
    end
    safe_join(parts, " · ".html_safe)
  end

  # Rating of a booking's OWN explicit accounting-entry link (nil when unlinked
  # or the pair carries no signal). Only this one pair is rated -- never other
  # accounting entries.
  def booking_link_rating(booking)
    entry = booking.accounting_entry
    entry && Fin::DatevBookingMatcher.rate_pair(booking, entry)
  end

  # Muted help text under the linked Beitragsbuchung: WHEN the link was made
  # (created_at) and BY WHOM (author_id) -- both from datev_booking_link_meta on
  # the entry. The HOW (classification_string) is deliberately NOT shown here --
  # it is already conveyed next to the lock icon by the confidence chip's basis.
  # Both the DATEV import and a UI connect record these; only links made before
  # that (or an edge case) have none, hence the fallback.
  def booking_link_provenance(booking)
    entry = booking.accounting_entry
    meta = entry&.datev_booking_link_meta
    return "Verknüpfungs-Metadaten nicht erfasst" if meta.blank?

    parts = []
    if (ts = meta["created_at"]) && (at = Time.zone.parse(ts.to_s))
      parts << "verknüpft am #{fin_date_time(at)}"
    end
    if (pid = meta["author_id"])
      person = ((@_link_person_cache ||= {})[pid] ||= Person.find_by(id: pid))
      parts << "durch #{person ? person.to_s : "Person ##{pid}"}"
    end
    parts.presence&.join(" · ") || "Verknüpfungs-Metadaten nicht erfasst"
  end

  # --- fin_detail formatters (fin_format_datev_booking_*) ---------------------

  # Betrag: the base-currency (EUR) figure, then the booking's Soll/Haben
  # written out and set apart from the number, so the two are read as two
  # things rather than as one string.
  def fin_format_datev_booking_base_amount(booking)
    amount = fin_money(booking.base_amount, booking.base_currency)
    return nil if amount.blank?

    label = debit_credit_long_label(booking.debit_credit)
    return amount if label.blank?

    safe_join([amount, content_tag(:span, label, class: "ms-3 text-muted")])
  end

  # Original-Betrag: the amount AS BOOKED, in the booking's own currency. Shown
  # only where that currency is not the base one -- on an EUR booking it would
  # repeat the Betrag -- and without a Soll/Haben of its own: the Betrag above
  # states it once, for the booking, and the figure carries its own currency.
  def fin_format_datev_booking_transaction_amount(booking)
    return nil unless booking_foreign_currency?(booking)

    fin_money(booking.transaction_amount, booking.transaction_currency)
  end

  # Notizen (user_comment): escaped, line breaks kept, URLs linked -- and, for a
  # viewer who holds :log on the booking (the audit tier and up), the FIN-/HELP-
  # ticket keys of the helpdesk as well (ContractHelper#auto_link_escaped_multiline).
  # A unit leader holds no :log on a booking and reads the keys as plain text.
  def fin_format_datev_booking_user_comment(booking)
    text = booking.user_comment
    return nil if text.blank?
    return auto_link_escaped_multiline(text) if can?(:log, booking)

    auto_link(html_escape_multiline(text), sanitize: false, html: {target: "_blank"}).html_safe
  end

  # Wechselkurs: the rate that turned the Original-Betrag into the Betrag, and
  # it belongs to that pair -- on an EUR booking the two amounts are the same
  # figure, so there is no rate to state and the row stays away with them.
  def fin_format_datev_booking_exchange_rate(booking)
    return nil unless booking_foreign_currency?(booking)

    booking_fx_rate_display(booking.exchange_rate)
  end

  def fin_format_datev_booking_account_number(booking)
    booking_account_cell(booking.account_number, booking.account_kind)
  end

  def fin_format_datev_booking_offsetting_account_number(booking)
    booking_account_cell(booking.offsetting_account_number, booking.offsetting_account_kind)
  end

  def fin_format_datev_booking_cost_center_number(booking)
    datev_code_cell(booking.cost_center_number, datev_cost_center_names)
  end

  def fin_format_datev_booking_secondary_cost_center_number(booking)
    datev_code_cell(booking.secondary_cost_center_number, datev_cost_center_names)
  end

  # The RESOLVED answer, always: the value first, then where it comes from in
  # parentheses -- "ja (Buchung)" where the booking carries the flag itself,
  # "nein (automatisch, Kostenstelle 9500)" where the cost center settled it,
  # "nein (automatisch, Konto 66500)" where one account decided, and the bare
  # "ja (automatisch)" where both agreed (#unit_budget_source_label). The field
  # is therefore never blank and stands on a reading page like any other, which
  # is the point: a booking has a Unit-Budget answer whether or not anybody
  # stored one on it.
  def fin_format_datev_booking_is_unit_budget(booking)
    value, source = booking.unit_budget
    origin = unit_budget_source_label(booking, source)
    unless source == DatevBooking::UNIT_BUDGET_SOURCE_BOOKING
      origin = ["automatisch", origin].compact_blank.join(", ")
    end
    "#{unit_budget_answer(value)} (#{origin})"
  end

  # The three choices of the edit page's select. The first one leaves the
  # booking's own flag unset and lets the cost center and the accounts decide --
  # it therefore names the answer they currently give, so the choice reads as
  # what it does.
  def fin_unit_budget_select_options(booking)
    automatic, = booking.automatic_unit_budget
    [["automatisch (#{unit_budget_answer(automatic)})", ""], ["ja", "true"], ["nein", "false"]]
  end

  # The sub cost center, read within the booking's own cost center. A pair that
  # does not resolve -- a DATEV import moved the booking to another cost center
  # -- keeps its raw number and is marked, rather than shown as unset.
  def fin_format_datev_booking_sub_cost_center_number(booking)
    number = booking.sub_cost_center_number
    return nil if number.blank?

    sub = booking.sub_cost_center
    return sub.to_s if sub

    safe_join([number, content_tag(:span, "(unbekannt)", class: "text-danger")], " ")
  end

  # The sub cost centers assignable to this booking: those of its OWN cost
  # center, since a sub cost center number is unique within its cost center
  # only. Like fin_cost_center_select_options appends the booked-but-unknown
  # numbers, the booking's current value is appended when it does not resolve,
  # so a stale pair is offered back instead of being dropped by the form.
  def fin_sub_cost_center_select_options(booking)
    opts = [["nicht gesetzt", ""]]
    if booking.cost_center_number.present?
      WsjrdpSubCostCenter.where(cost_center_number: booking.cost_center_number)
        .order(:number).each { |sub| opts << [sub.to_s, sub.number] }
    end
    current = booking.sub_cost_center_number
    opts << [current, current] if current.present? && opts.none? { |(_, value)| value == current }
    opts
  end

  # The edit page's second sub cost center control, rendered next to the select
  # (`extra:` of the field, Fin::DetailHelper#fin_detail_edit_field): the NUMBER
  # of a sub cost center to create under this booking's own cost center. Given,
  # it wins over the select -- a number that does not exist yet cannot be among
  # its options (Fin::BookingDetailHost#resolve_new_sub_cost_center).
  def fin_new_sub_cost_center_field(_form, _row)
    text_field_tag(Fin::BookingDetailHost::NEW_SUB_COST_CENTER_PARAM, nil,
      placeholder: "neue Unter-Kostenstelle", class: "form-control form-control-sm",
      style: "max-width: 12ch")
  end

  def fin_cost_center_select_options
    names = WsjrdpCostCenter.order(:number).pluck(:number, :name).to_h
    booked = DatevBooking.where.not(cost_center_number: nil).distinct.pluck(:cost_center_number) +
      DatevBooking.where.not(secondary_cost_center_number: nil).distinct.pluck(:secondary_cost_center_number)
    opts = [["nicht gesetzt", ""]]
    names.each { |n, name| opts << [name.present? ? "#{n} #{name}" : n, n] }
    (booked.uniq - names.keys).sort.each { |n| opts << [n, n] }
    opts
  end
end
