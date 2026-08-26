# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Reusable helpers for listing DatevBookings: a column registry (label +
# alignment + which are sortable), the selectable-column logic, and per-cell
# formatting. Rendering itself uses hitobito's StandardTableBuilder in the
# shared `fin/bookings/_bookings_table` partial.
module WsjrdpBookingsHelper
  # key: the DatevBooking column (or "account_name", a derived column);
  # label: the header; numeric: right-align. A column is sortable iff its key
  # is in DatevBookingsQuery::SORTABLE.
  # width: fixed CSS width for table-layout:fixed (nil => share remaining space).
  BookingColumn = Struct.new(:key, :label, :numeric, :width, keyword_init: true) do
    def sortable?
      DatevBookingsQuery::SORTABLE.key?(key)
    end
  end

  # Note: "Konto" (account_number) always renders number + name, so there is no
  # separate "Kontobezeichnung" column. Primanota (primanota_number) is
  # intentionally not offered as a column.
  # Selectable columns for the bookings table / picker. account_type,
  # offsetting_account_type, KOST1/KOST2 and the raw Buchungstext are purely
  # internal and are shown only in the (untouched) detail view, not as columns.
  ALL_BOOKING_COLUMNS = [
    BookingColumn.new(key: "booking_date", label: "Datum", width: "7rem"),
    BookingColumn.new(key: "service_date", label: "Leistungsdatum", width: "7rem"),
    BookingColumn.new(key: "amount", label: "Betrag", numeric: true, width: "8rem"),
    BookingColumn.new(key: "description", label: "Beschreibung", width: "16rem"),
    BookingColumn.new(key: "cost_center_number", label: "Kostenstelle", width: "9rem"),
    BookingColumn.new(key: "secondary_cost_center_number", label: "Sekundäre Kostenstelle", width: "11rem"),
    BookingColumn.new(key: "account_number", label: "Konto", width: "13rem"),
    BookingColumn.new(key: "offsetting_account_number", label: "Gegenkonto", width: "13rem"),
    BookingColumn.new(key: "document_field_1", label: "Belegfeld 1", width: "9rem"),
    BookingColumn.new(key: "document_field_2", label: "Belegfeld 2", width: "9rem"),
    BookingColumn.new(key: "primanota_period", label: "Primanota Periode", width: "8.5rem"),
    BookingColumn.new(key: "sphere_number", label: "Sphäre", width: "5rem")
  ].freeze

  # Action (eye / delete-marker) column width, in rem.
  ACTION_COLUMN_REM = 2.75

  # Shown initially; every other column (Leistungsdatum, Periode, Status, the
  # KOST/Belegfeld codes, ...) is available via the column picker.
  DEFAULT_BOOKING_COLUMN_KEYS = %w[
    booking_date amount description cost_center_number account_number offsetting_account_number
  ].freeze

  # Condensed (in-detail) table: abbreviated headers, since only the code is shown
  # there (no account / cost-center / supplier name). The condensed table sizes its
  # columns to content (table-layout: auto), so it carries no fixed widths.
  CONDENSED_LABELS = {
    "cost_center_number" => "KSt",
    "secondary_cost_center_number" => "KSt 2",
    "account_number" => "Kto",
    "offsetting_account_number" => "Gkto"
  }.freeze

  def all_booking_columns
    ALL_BOOKING_COLUMNS
  end

  # The bookings columns as the generic shared/_expandable_table column config
  # (key/label/cell/…). `condensed` bakes the compact cell formatting + the
  # abbreviated headers used inside a detail view. css_class "bkcol-<key>" keeps
  # the responsive per-column hiding in the shared styles working.
  def booking_table_columns(query, condensed: false)
    all_booking_columns.map do |col|
      {
        key: col.key,
        abbr: DatevBookingsQuery::COLUMN_ABBREVIATIONS[col.key] || col.key,
        label: col.label,
        condensed_label: CONDENSED_LABELS[col.key],
        numeric: col.numeric,
        width: col.width,
        css_class: "bkcol-#{col.key}",
        sort_key: (col.sortable? ? col.key : nil),
        cell: ->(booking) { booking_cell(booking, col.key, condensed: condensed) }
      }
    end
  end

  # Open state of a collapsible pane, remembered via cookie (JS sets it on
  # toggle). Only an explicit collapse closes it -- not filtering / column
  # changes / pagination.
  def booking_pane_open?(name, default:)
    value = cookies["datev_bookings_pane_#{name}"]
    value.nil? ? default : value == "1"
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
    when "amount"
      booking_amount_with_currency(booking)
    when "booking_date", "service_date"
      booking.public_send(key)&.strftime("%d.%m.%Y")
    when "primanota_period"
      booking.primanota_period&.strftime("%Y-%m")
    when "account_number", "offsetting_account_number"
      datev_code_cell(booking.public_send(key), datev_account_names, condensed: condensed)
    when "cost_center_number", "secondary_cost_center_number"
      datev_code_cell(booking.public_send(key), datev_cost_center_names, condensed: condensed)
    else
      booking.public_send(key)
    end
  end

  # Amount with its currency code (EUR / PLN / ...), never the "€" symbol.
  # `amount` is the signed base-currency (EUR) value (incoming +, outgoing -).
  def booking_amount_with_currency(booking)
    # A legs-backed row (account/supplier detail) carries `leg_amount` -- the
    # value from THAT account's own perspective; a plain row has only `amount`.
    amount = booking.has_attribute?(:leg_amount) ? booking.leg_amount : booking.amount
    formatted = eur_display_or_nil(amount)
    return formatted if formatted.blank?
    unit = booking.base_currency
    primary = "#{formatted} #{unit}"
    # Foreign-currency booking: base (EUR) amount on the first line, the as-booked
    # SIGNED transaction amount + currency muted on a second line -- only when the
    # transaction currency actually differs from the base currency.
    return primary unless booking_foreign_currency?(booking)
    tx = booking_amount_currency_str(booking.transaction_amount, booking.transaction_currency)
    safe_join([primary, content_tag(:div, tx, class: "text-muted small")])
  end

  # True when the booking was made in a currency other than the base (EUR).
  def booking_foreign_currency?(booking)
    booking.transaction_currency != booking.base_currency
  end

  # "<amount> <currency>" (e.g. "123,40 EUR" / "-2.700,00 PLN"), or nil if blank.
  def booking_amount_currency_str(amount, currency)
    [eur_display_or_nil(amount), currency.presence].compact.join(" ").presence
  end

  # Human label for a DATEV "Kontenart" code (BANK, EXPENSE, ...). Falls back to
  # the raw code stored in the DB when no translation exists.
  def account_type_label(code)
    return nil if code.blank?
    I18n.t("fin.account_type.#{code}", default: code)
  end

  # Translated status ("active"/"deactivated"/...); falls back to the code.
  def fin_status_label(status)
    return nil if status.blank?
    I18n.t("fin.status.#{status}", default: status.humanize)
  end

  # German label for the canonical English debit_credit code: "D" -> "Soll",
  # "C" -> "Haben"; falls back to the raw code.
  def debit_credit_label(code)
    return nil if code.blank?
    I18n.t("fin.debit_credit.#{code}", default: code)
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

  # Sortable column header link (same :sort / :sort_dir convention as hitobito),
  # preserving all current filters / columns and resetting the page.
  def booking_sort_link(query, column, condensed: false)
    label = booking_column_label(column, condensed: condensed)
    return label unless column.sortable?

    current = query.sort_column == column.key
    arrow = ""
    arrow = (query.sort_direction == "asc") ? " ↑" : " ↓" if current
    next_dir = (current && query.sort_direction == "asc") ? "desc" : "asc"
    target = request.query_parameters.except("page")
      .merge("sort" => column.key, "sort_dir" => next_dir)
    # Stay on the current page (main list or per-account page); the account, when
    # present, lives in the path, not in the query string.
    link_to "#{label}#{arrow}", "#{request.path}?#{target.to_query}",
      class: ["text-reset text-decoration-none", ("fw-semibold" if current)].compact
  end

  # The booking detail grid, as explicit rows of cells. Each cell is
  # [label, value], [label, value, span] or [label, value, span, align] (span
  # defaults to 1, span 2 = double-width; align :end right-aligns the value). A
  # nil label renders an empty placeholder cell. Values may be HTML (account /
  # cost-center cells) or plain; blanks -> "—" in the view.
  def booking_detail_field_rows(booking)
    rows = [
      [
        ["Buchungsdatum", booking.booking_date&.strftime("%d.%m.%Y")],
        ["Leistungsdatum", booking.service_date&.strftime("%d.%m.%Y")],
        ["Beschreibung", booking.description, 2]
      ],
      [
        ["Betrag", booking_amount_currency_str(booking.absolute_base_amount, booking.base_currency), 1, :end],
        ["S/H", debit_credit_label(booking.debit_credit)],
        ["Konto", booking_account_cell(booking.account_number, booking.account_type)],
        ["Gegenkonto", booking_account_cell(booking.offsetting_account_number, booking.offsetting_account_type)]
      ]
    ]
    # Foreign-currency booking (special case): the as-booked transaction figures,
    # placed directly below the Betrag row so they sit close to it. The
    # Transaktionsbetrag is sign-less, matching the sign-less Betrag above.
    if booking_foreign_currency?(booking)
      rows << [
        ["Transaktionsbetrag",
          booking_amount_currency_str(booking.absolute_transaction_amount, booking.transaction_currency), 1, :end],
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

  # "Betrag / S/H" cell: the sign-less base-currency (EUR) amount with the S/H
  # flag appended, e.g. "123,40 S" or "0,73 H" (no currency). Used in the compact
  # reconciliation autocomplete labels.
  def booking_base_amount_with_sh(booking)
    [eur_display_or_nil(booking.absolute_base_amount), debit_credit_label(booking.debit_credit)]
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
  # when it differs from the description. Blank values are dropped by the view.
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
        booking.original_posting_text != booking.description
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
    # other_datev_fields JSONB; surfaced here so nothing from the export is hidden.
    booking.other_datev_fields.each do |name, value|
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
  def booking_account_cell(number, account_type)
    cell = datev_code_cell(number, datev_account_names)
    return cell if cell.blank?
    type = account_type_label(account_type)
    return cell if type.blank?
    safe_join([cell, content_tag(:span, "(#{type})", class: "text-muted")], " ")
  end

  # --- Match rating (shared with fin/reconciliation/participant_fees) --------

  # Per-tier chip appearance (see DatevBookingMatcher::Match#tier and
  # doc/recon_linking.md). Four visually distinct colours: :automatic a firm
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
  # accounting entries. ignore_person_link: rate the actual textual evidence, not
  # the trivial "person already on the booking" match (an existing link always
  # has the person set, which would otherwise force a meaningless 100 %).
  def booking_link_rating(booking)
    entry = booking.accounting_entry
    entry && DatevBookingMatcher.rate_pair(booking, entry, ignore_person_link: true)
  end

  # Muted help text under the linked Beitragsbuchung: WHEN the link was made
  # (accounting_entry_linked_at) and BY WHOM (accounting_entry_link_person_id).
  # The HOW (accounting_entry_link_type) is deliberately NOT shown here -- it is
  # already conveyed next to the lock icon by the confidence chip's basis. Both
  # the DATEV import and a UI connect record these; only links made before that
  # (or an edge case) have none, hence the fallback text.
  def booking_link_provenance(booking)
    parts = []
    if booking.accounting_entry_linked_at
      parts << "verknüpft am #{booking.accounting_entry_linked_at.strftime("%d.%m.%Y %H:%M")}"
    end
    if (pid = booking.accounting_entry_link_person_id)
      person = ((@_link_person_cache ||= {})[pid] ||= Person.find_by(id: pid))
      parts << "durch #{person ? person.to_s : "Person ##{pid}"}"
    end
    parts.presence&.join(" · ") || "Verknüpfungs-Metadaten nicht erfasst"
  end
end
