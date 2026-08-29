# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Cell rendering and inline-detail rendering for the Buchhaltung summary tables
# (Sachkonten, Kostenstellen, Kreditoren). What a column IS -- label, width,
# wire token, sort extractor, shown by default -- lives in
# Fin::BookkeepingSummaryColumns; this module only adds the cells, which need
# the lookup maps (account_kinds, ledger_account_records, ...) of the
# Buchhaltung resource controllers (Fin::LedgerAccountsController,
# Fin::CostCentersController, Fin::PersonalAccountsController).
module Fin::BookkeepingHelper
  def bookkeeping_muted_dash
    content_tag(:span, "—", class: "text-muted")
  end

  # The Summe / Saldo cell of the three summaries, in the money format of the
  # Finanzen lists (Fin::MoneyHelper): the number and the currency's symbol.
  def bookkeeping_sum_cell(value) = fin_money(value)

  # The detail view of an item (currently the Sachkonten): a list of metadata
  # fields plus the item's embedded, paged bookings table (a
  # Wsjrdp::ExpandableTableRows, see fin/bookings/_embedded). Rendered the same
  # way inline (lazy-loaded detail row) and on the dedicated page. Kreditoren and
  # Kostenstellen build their detail through the shared kit instead
  # (fin/personal_accounts/_detail, fin/cost_centers/_detail,
  # Fin::DetailHelper).
  def bookkeeping_item_detail(fields:, item_bookings:, show_all_path:, all_label:)
    render "fin/shared/item_detail", fields: fields, item_bookings: item_bookings,
      show_all_path: show_all_path, all_label: all_label
  end

  def account_item_detail(number)
    bookkeeping_item_detail(fields: account_detail_fields(number),
      item_bookings: account_bookings(number),
      # The embedded list shows the account's legs on EITHER side
      # (DatevBooking.legs), so the link asks for "Konto oder Gegenkonto".
      show_all_path: bookings_filter_path([[["any_account", "in", number]]]),
      all_label: "In Buchungen-Ansicht öffnen")
  end

  # "In Buchungen-Ansicht öffnen": the Buchungen listing (fin/bookings) pinned
  # to this item. The Buchungen page reads its filter from the ?f= param alone
  # (Rison, short keys -- doc/wsjrdp/generic_filter_builder.md §2.8), so the
  # link carries a long-form CNF tree encoded through the bookings page's OWN
  # schema and its own param name; a renamed attribute or field letter can
  # therefore not leave a stale link here. Encoding against the schema REDUCED
  # by the bookings page's exclude list is the same schema that page decodes
  # with, so nothing is encoded that would be dropped on arrival. `tree` is
  # long-form ([[[attribute, operator, *operands]]]); slots are ANDed,
  # conditions inside a slot ORed. Encoding is tolerant and yields nil when
  # nothing survives -- then the link goes to the unfiltered listing.
  def bookings_filter_path(tree)
    schema = Fin::DatevBookingsFilterSchema.bound(
      except: Fin::BookingsController::EXCLUDED_FILTER_ATTRIBUTES
    )
    rison = Fin::DatevBookingsFilterSchema.encode_tree(tree, schema: schema)
    return bookings_path if rison.blank?

    param = Fin::BookingsController::BOOKINGS_POLICY.param_name(:filter)
    "#{bookings_path}?#{param}=#{Wsjrdp::Filtering::UrlCodec.escape_for_query(rison)}"
  end

  # [label, value] metadata pairs (blank values are dropped in the partial).
  def account_detail_fields(number)
    a = ledger_account_records[number]
    [["Bezeichnung", a&.name], ["Kurzname", a&.short_name],
      ["Kontoart", account_kind_label(a&.account_kind)]]
  end

  # Metadata of a Buchungsstapel (DATEV booking batch). [label, value] pairs;
  # blank values are dropped by shared/_detail_fields.
  def booking_batch_detail_fields(batch)
    period = [batch.period_from, batch.period_to].map { |d| fin_date(d) }
      .compact.join(" – ")
    [
      ["Bezeichnung", batch.label],
      ["Zeitraum", period],
      ["Berater", batch.consultant_number],
      ["Mandant", batch.client_number],
      ["Wirtschaftsjahr-Beginn", fin_date(batch.financial_year_start)],
      ["Sachkontenlänge", batch.ledger_account_number_length],
      ["Kontenrahmen", batch.datev_chart_of_accounts_number],
      ["Währung", batch.base_currency],
      ["Buchungstyp", batch.booking_type],
      ["Herkunft (HK)", batch.origin_indicator],
      ["Primanota-Nr.", batch.primanota_number],
      ["Festschreibung", (batch.is_finalized ? "ja" : "nein")],
      ["DATEV-Erstellung", fin_date_time(batch.datev_created_at)],
      ["Quelldatei", batch.source_file]
    ]
  end

  # The three summary tables as shared/_expandable_table column configs: the
  # descriptions of Fin::BookkeepingSummaryColumns plus this page's cells.
  #
  # The Sachkonten table is RELATION-backed
  # (WsjrdpLedgerAccount.with_booking_summary), so its cells receive a
  # WsjrdpLedgerAccount carrying the two aggregate columns, and nothing needs a
  # per-page name lookup.
  def sachkonten_columns
    summary_columns(Fin::BookkeepingSummaryColumns::LEDGER_ACCOUNTS,
      "number" => ->(a) { a.number },
      "name" => ->(a) { a.name.presence || bookkeeping_muted_dash },
      "short_name" => ->(a) { a.short_name.presence || bookkeeping_muted_dash },
      "account_kind" => ->(a) { account_kind_label(a.account_kind).presence || bookkeeping_muted_dash },
      "moss_status" => ->(a) { moss_status_cell(a.moss_status) },
      "booking_sum" => ->(a) { bookkeeping_sum_cell(a.booking_sum) },
      "booking_count" => ->(a) { a.booking_count })
  end

  # The Kostenstellen table is RELATION-backed
  # (WsjrdpCostCenter.with_booking_summary), so its cells receive a
  # WsjrdpCostCenter carrying the two aggregate columns, not a row Hash.
  def kostenstellen_columns
    summary_columns(Fin::BookkeepingSummaryColumns::COST_CENTERS,
      "number" => ->(c) { c.number },
      "name" => ->(c) { c.name.presence || bookkeeping_muted_dash },
      "short_name" => ->(c) { c.short_name.presence || bookkeeping_muted_dash },
      "moss_status" => ->(c) { moss_status_cell(c.moss_status) },
      "booking_sum" => ->(c) { bookkeeping_sum_cell(c.booking_sum) },
      "booking_count" => ->(c) { c.booking_count })
  end

  # The Kreditoren table is relation-backed as well, so its cells receive a
  # WsjrdpPersonalAccount (with the two aggregate columns of
  # .with_booking_summary) and nothing needs a per-page name lookup.
  def kreditoren_columns
    summary_columns(Fin::BookkeepingSummaryColumns::PERSONAL_ACCOUNTS,
      "number" => ->(a) { a.number },
      "name" => ->(a) { a.name.presence || bookkeeping_muted_dash },
      "moss_status" => ->(a) { moss_status_cell(a.moss_status) },
      "booking_balance" => ->(a) { bookkeeping_sum_cell(a.booking_balance) },
      "booking_count" => ->(a) { a.booking_count })
  end

  def buchungsstapel_columns
    summary_columns(Fin::BookingBatchesColumns::BATCHES,
      "label" => ->(b) { b.label },
      "period" => ->(b) { b.period_to&.strftime("%Y-%m") || bookkeeping_muted_dash },
      "primanota_number" => ->(b) { b.primanota_number.presence || bookkeeping_muted_dash },
      "period_from" => ->(b) { fin_date(b.period_from) || bookkeeping_muted_dash },
      "period_to" => ->(b) { fin_date(b.period_to) || bookkeeping_muted_dash },
      "booking_count" => ->(b) { b.booking_count },
      "is_finalized" => ->(b) { b.is_finalized ? "ja" : "nein" })
  end

  # THE "Moss Status" cell of the three summary tables (Sachkonten,
  # Kostenstellen and Kreditoren): the word alone, tinted -- a muted green for
  # aktiv, the muted grey for inaktiv. Colour is never the only cue; the word
  # says the same thing. The colours live in shared/wsjrdp/_moss_status_styles,
  # which every page showing such a cell renders.
  def moss_status_cell(status)
    variant = moss_status_active?(status) ? "active" : "inactive"
    content_tag(:span, moss_status_label(status), class: "moss-status moss-status-#{variant}")
  end

  # The two values a summary list knows -- aktiv and inaktiv -- where a record
  # Moss does not know at all (moss_status NULL) counts as inaktiv, exactly like
  # the COALESCE the filter attribute and the column's sort use.
  # (fin_status_label stays for the places that show the raw Moss status of any
  # record, e.g. the detail formatters of Fin::CostCentersHelper and
  # Fin::PersonalAccountsHelper.)
  def moss_status_label(status)
    I18n.t("fin.moss_status.#{moss_status_active?(status) ? "active" : "deactivated"}")
  end

  # WsjrdpCostCenter and WsjrdpPersonalAccount spell the two Moss states
  # identically, so one comparison serves both pages.
  def moss_status_active?(status)
    status == WsjrdpCostCenter::STATUS_ACTIVE
  end

  # Pairs each described column with its cell. `cells` is keyed by column key and
  # is fetched, so a column without a cell (or a cell without a column) raises
  # here instead of rendering an empty table cell.
  def summary_columns(columns, cells)
    columns.map { |col| col.to_table_column(cell: cells.fetch(col.key)) }
  end
end
