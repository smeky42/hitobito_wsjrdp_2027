# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Column definitions and inline-detail rendering for the Buchhaltung summary
# tables (Sachkonten, Kostenstellen, Kreditoren). Each column is a hash consumed
# by shared/_expandable_table: { label:, width:, numeric:, cell: ->(row){..} }.
# The lookup maps (account_types, cost_center_info, ...) come from the
# Buchhaltung resource controllers (Fin::LedgerAccountsController,
# Fin::CostCentersController, Fin::PersonalAccountsController).
module WsjrdpBookkeepingHelper
  def bookkeeping_muted_dash
    content_tag(:span, "—", class: "text-muted")
  end

  def bookkeeping_sum_cell(value)
    "#{eur_display_or_nil(value)} EUR"
  end

  # The detail view of an item (ledger account / cost center / supplier): a list
  # of metadata fields plus the embedded, paged bookings (see fin/bookings/_embedded).
  # Rendered the same way inline (lazy-loaded detail row) and on the dedicated page.
  def bookkeeping_item_detail(fields:, query:, show_all_path:, all_label:)
    render "fin/shared/item_detail",
      fields: fields, query: query, show_all_path: show_all_path, all_label: all_label
  end

  def account_item_detail(number)
    bookkeeping_item_detail(fields: account_detail_fields(number),
      query: account_bookings_query(number),
      show_all_path: bookings_path(account_number: [number]),
      all_label: "In Buchungen-Ansicht öffnen")
  end

  def cost_center_item_detail(number)
    bookkeeping_item_detail(fields: cost_center_detail_fields(number),
      query: cost_center_bookings_query(number),
      show_all_path: bookings_path(cost_center: [number]),
      all_label: "In Buchungen-Ansicht öffnen")
  end

  def supplier_item_detail(number)
    bookkeeping_item_detail(fields: supplier_detail_fields(number),
      query: supplier_bookings_query(number),
      show_all_path: bookings_path(offsetting_account_number: [number]),
      all_label: "In Buchungen-Ansicht öffnen")
  end

  # [label, value] metadata pairs (blank values are dropped in the partial).
  def account_detail_fields(number)
    a = ledger_account_records[number]
    [["Bezeichnung", a&.name], ["Kurzname", a&.short_name],
      ["Kontoart", account_type_label(a&.account_type)]]
  end

  def cost_center_detail_fields(number)
    c = cost_center_records[number]
    [["Bezeichnung", c&.name], ["Moss Status", fin_status_label(c&.moss_status)]]
  end

  def supplier_detail_fields(number)
    s = supplier_records[number]
    return [] unless s
    [["Name", s.name], ["Moss Status", fin_status_label(s.moss_status)],
      ["Kontoinhaber", s.moss_account_holder_name], ["IBAN", s.iban], ["BIC", s.bic],
      ["USt-IdNr.", s.moss_vat_id], ["Zahlungsart", s.moss_default_payment_method],
      ["Standard-Konto", s.moss_default_ledger_account_number],
      ["Standard-Kostenstelle", s.moss_default_cost_center_number],
      ["Standard-Sphäre", s.moss_default_sphere_number], ["Team", s.moss_default_team_name],
      ["Adresse", bookkeeping_address(s)]]
  end

  # Metadata of a Buchungsstapel (DATEV booking batch). [label, value] pairs;
  # blank values are dropped by shared/_detail_fields.
  def booking_batch_detail_fields(batch)
    period = [batch.period_from, batch.period_to].map { |d| d&.strftime("%d.%m.%Y") }
      .compact.join(" – ")
    [
      ["Bezeichnung", batch.label],
      ["Zeitraum", period],
      ["Berater", batch.consultant_number],
      ["Mandant", batch.client_number],
      ["Wirtschaftsjahr-Beginn", batch.fiscal_year_start&.strftime("%d.%m.%Y")],
      ["Sachkontenlänge", batch.account_number_length],
      ["Kontenrahmen", batch.chart_of_accounts],
      ["Währung", batch.currency],
      ["Buchungstyp", batch.booking_type],
      ["Herkunft (HK)", batch.origin_indicator],
      ["Primanota-Nr.", batch.primanota_number],
      ["Festschreibung", (batch.festschreibung ? "ja" : "nein")],
      ["DATEV-Erstellung", batch.datev_created_at&.strftime("%d.%m.%Y %H:%M")],
      ["Quelldatei", batch.source_file]
    ]
  end

  def bookkeeping_address(supplier)
    [supplier.street, [supplier.post_code, supplier.city].compact_blank.join(" "),
      supplier.country].compact_blank.join(", ")
  end

  # Column configs for the three Buchhaltung summary tables. Each column carries a
  # stable `key:` (needed by the column hamburger) + a compact `abbr:` (the URL
  # token in the <prefix>_cols param) and, where sensible, a `sort_key:` (the
  # token in ?sort) -- see Fin::BookkeepingSummaries#sort_summary_rows for the
  # matching value extractors. The category column (Kontoart / Moss Status) is
  # intentionally left unsortable.
  def sachkonten_columns
    [
      {key: "number", abbr: "nr", label: "Konto", width: "8rem", sort_key: "number", cell: ->(r) { r[:number] }},
      {key: "name", abbr: "bez", label: "Bezeichnung", width: "18rem", sort_key: "name",
       cell: ->(r) { datev_account_full_names[r[:number]].presence || bookkeeping_muted_dash }},
      {key: "type", abbr: "art", label: "Kontoart", width: "9rem",
       cell: ->(r) { account_type_label(account_types[r[:number]]).presence || bookkeeping_muted_dash }},
      {key: "sum", abbr: "sum", label: "Summe (EUR)", numeric: true, width: "10rem", sort_key: "sum",
       cell: ->(r) { bookkeeping_sum_cell(r[:sum]) }},
      {key: "count", abbr: "cnt", label: "Buchungen", numeric: true, width: "7rem", sort_key: "count", cell: ->(r) { r[:count] }}
    ]
  end

  def kostenstellen_columns
    [
      {key: "number", abbr: "nr", label: "Kostenstelle", width: "9rem", sort_key: "number", cell: ->(r) { r[:number] }},
      {key: "name", abbr: "bez", label: "Bezeichnung", width: "18rem", sort_key: "name",
       cell: ->(r) { cost_center_info.dig(r[:number], :name).presence || bookkeeping_muted_dash }},
      {key: "status", abbr: "st", label: "Moss Status", width: "8rem",
       cell: ->(r) { fin_status_label(cost_center_info.dig(r[:number], :moss_status)) || bookkeeping_muted_dash }},
      {key: "sum", abbr: "sum", label: "Summe (EUR)", numeric: true, width: "10rem", sort_key: "sum",
       cell: ->(r) { bookkeeping_sum_cell(r[:sum]) }},
      {key: "count", abbr: "cnt", label: "Buchungen", numeric: true, width: "7rem", sort_key: "count", cell: ->(r) { r[:count] }}
    ]
  end

  def kreditoren_columns
    [
      {key: "number", abbr: "nr", label: "Kreditor", width: "9rem", sort_key: "number", cell: ->(r) { r[:number] }},
      {key: "name", abbr: "bez", label: "Name", width: "18rem", sort_key: "name",
       cell: ->(r) { supplier_info.dig(r[:number], :name).presence || bookkeeping_muted_dash }},
      {key: "status", abbr: "st", label: "Moss Status", width: "8rem",
       cell: ->(r) { fin_status_label(supplier_info.dig(r[:number], :moss_status)) || bookkeeping_muted_dash }},
      {key: "sum", abbr: "sum", label: "Summe (EUR)", numeric: true, width: "10rem", sort_key: "sum",
       cell: ->(r) { bookkeeping_sum_cell(r[:sum]) }},
      {key: "count", abbr: "cnt", label: "Buchungen", numeric: true, width: "7rem", sort_key: "count", cell: ->(r) { r[:count] }}
    ]
  end
end
