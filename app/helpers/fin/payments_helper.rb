# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The cells of the Zahlungsverkehr tables (doc/fin/payments.md): the orders,
# the debits and the returns, each as the widget's column Hashes over its
# column collection (Fin::PaymentOrdersColumns, Fin::DirectDebitsColumns,
# Fin::PaymentReturnsColumns), and the sums of their footers. The rows are
# the relations of Fin::PaymentQueries, whose figures arrive as attributes.
module Fin::PaymentsHelper
  # How many amounts a breakdown names at first, and how many more each click
  # on its "mehr" shows (#payment_count_with_breakdown).
  BREAKDOWN_LIMIT = 20

  # The order statuses under which the bank has the SEPA file, so a credit is
  # due.
  CREDIT_DUE_STATUSES = %w[xml_generated].freeze

  KIND_ICONS = {
    WsjrdpPaymentInitiation::DIRECT_DEBIT => :"file-signature",
    WsjrdpPaymentInitiation::CREDIT_TRANSFER => :landmark,
    WsjrdpPaymentInitiation::CONFLICT => :"exclamation-triangle",
    WsjrdpPaymentInitiation::UNKNOWN => :question
  }.freeze

  def payment_order_table_columns
    cells = {
      "id" => ->(order) { order.id },
      "kind" => ->(order) { payment_kind_cell(order.kind) },
      "account" => ->(order) { payment_account_cell(order) },
      "created_at" => ->(order) { fin_date_time(order.created_at) },
      "execution_date" => ->(order) {
        payment_order_stack(order, payment_date_range(order.first_date, order.last_date), same: :requested_collection_date, main: false) { |info| fin_date(info.requested_collection_date) }
      },
      "sequence" => ->(order) {
        payment_order_stack(order, payment_sequences(order.sequence_types), same: :debit_sequence_type, main: false) { |info| payment_sequences(info.debit_sequence_type) }
      },
      "count" => ->(order) {
        payment_order_stack(order, payment_count(order.number_of_transactions)) { |info| payment_count(info.number_of_transactions) }
      },
      "sum" => ->(order) {
        payment_order_stack(order, payment_cents(order.control_sum_cents)) { |info| payment_cents(info.control_sum_cents) }
      },
      "pre_notified_count" => ->(order) {
        payment_announced_cell(order, payment_count(order.notice_count), order.notice_count == order.number_of_transactions)
      },
      "pre_notified_sum" => ->(order) {
        payment_announced_cell(order, payment_cents(order.pre_notified_sum_cents),
          order.pre_notified_sum_cents == order.control_sum_cents)
      },
      "return_count" => ->(order) {
        payment_order_stack(order, payment_return_count(order.return_count)) { |info|
          payment_count(info.return_count) if info.return_count.to_i.positive?
        }
      },
      "returns" => ->(order) {
        payment_order_stack(order, payment_return_sum(order.return_count, order.return_sum_cents)) { |info|
          payment_return_sum(info.return_count, info.return_sum_cents) if info.return_count.to_i.positive?
        }
      },
      "status" => ->(order) { payment_status_label(order.status) },
      "bank" => ->(order) {
        payment_order_stack(order, payment_order_credit_cell(order), main: false) { |info| payment_info_credit_cell(info) }
      },
      "skipped" => ->(order) { payment_count(order.skipped_count) },
      "message_identification" => ->(order) { content_tag(:span, order.message_identification, class: "font-monospace") },
      "sepa_schema" => ->(order) { order.sepa_schema }
    }
    Fin::PaymentOrdersColumns::COLUMNS.map { |col| col.to_table_column(cell: cells.fetch(col.key)) }
  end

  def direct_debit_table_columns
    cells = {
      "person" => ->(debit) { payment_person(debit.subject) },
      "role" => ->(debit) { payment_role_cell(debit.payment_role) },
      "order" => ->(debit) { payment_order_link(debit.payment_initiation_id) },
      "collection_date" => ->(debit) { fin_date(debit.collection_date) },
      "sequence" => ->(debit) { debit.debit_sequence_type },
      "amount" => ->(debit) { payment_debit_amount_cell(debit) },
      "pre_notified_amount" => ->(debit) { payment_pre_notified_cell(debit) },
      "status" => ->(debit) { payment_status_label(debit.payment_status) },
      "entry" => ->(debit) { payment_entry_mark(debit.entry_id) },
      "return" => ->(debit) { payment_debit_return_cell(debit) },
      "dbtr_name" => ->(debit) { debit.dbtr_name },
      "dbtr_iban" => ->(debit) { content_tag(:span, debit.dbtr_iban, class: "font-monospace") },
      "mandate_id" => ->(debit) { content_tag(:span, debit.mandate_id, class: "font-monospace") },
      "description" => ->(debit) { debit.description },
      "endtoend_id" => ->(debit) { content_tag(:span, debit.endtoend_id, class: "font-monospace") },
      "email_to" => ->(debit) { debit.email_to },
      "id" => ->(debit) { debit.id }
    }
    Fin::DirectDebitsColumns::COLUMNS.map { |col| col.to_table_column(cell: cells.fetch(col.key)) }
  end

  def payment_return_table_columns
    cells = {
      "person" => ->(ret) { payment_person(ret.subject) },
      "date" => ->(ret) { fin_date(ret.booking_date || ret.value_date) },
      "amount" => ->(ret) { payment_cents(ret.amount_cents) },
      "reason" => ->(ret) { payment_return_reasons(ret.return_reason, long: true) },
      "debit" => ->(ret) { payment_return_debit_cell(ret) },
      "order" => ->(ret) { payment_order_link(ret.order_id) },
      "entry" => ->(ret) { payment_return_entry_cell(ret.return_entry_id) },
      "status" => ->(ret) { payment_return_status_cell(ret) },
      "endtoend_id" => ->(ret) { content_tag(:span, ret.endtoend_id, class: "font-monospace") },
      "mandate_id" => ->(ret) { content_tag(:span, ret.mandate_id, class: "font-monospace") },
      "description" => ->(ret) { ret.description },
      "id" => ->(ret) { ret.id }
    }
    Fin::PaymentReturnsColumns::COLUMNS.map { |col| col.to_table_column(cell: cells.fetch(col.key)) }
  end

  # A bank transaction's ISO code ("PMNT+ICDT+RRTN") and under it, small and
  # muted, the German labels of its parts -- the English names of the ISO list
  # as tooltip (Fin::BankTransactionCodes); a part not listed shows its code.
  def payment_iso_code(code)
    return nil if code.blank?

    parts = Fin::BankTransactionCodes.iso_parts(code)
    payment_code_with_meaning(code, parts.map { |part| part.label || part.code },
      parts.map { |part| part.name || part.code })
  end

  # The code of the German banks ("NRTI+159+00931") and under it the meaning of
  # its SWIFT code, its GVC and a Textschlüsselergänzung -- without the
  # Primanota, a batch number of the bank.
  def payment_dk_code(code)
    return nil if code.blank?

    parts = Fin::BankTransactionCodes.dk_parts(code)
    labels = payment_dk_code_texts(parts, :label)
    payment_code_with_meaning(code, labels, payment_dk_code_texts(parts, :name))
  end

  def payment_dk_code_texts(parts, field)
    [
      parts[:swift] && [parts[:swift].code, parts[:swift].public_send(field)].compact.join(" "),
      parts[:gvc] && ["GVC #{parts[:gvc].code}", parts[:gvc].public_send(field)].compact.join(" "),
      parts[:text_key] && t("fin.payments.text_key", code: parts[:text_key].code)
    ].compact
  end

  def payment_code_with_meaning(code, labels, names)
    safe_join([content_tag(:span, code, class: "font-monospace"),
      content_tag(:div, labels.join(" · "), class: "small text-muted", title: names.join(" · "))])
  end

  # The meaning of a code cell of a list: its German labels and, in a second
  # line, the English names -- a tooltip.
  def payment_codes_tooltip(ret)
    parts = Fin::BankTransactionCodes.iso_parts(ret.bank_transaction_code)
    dk = Fin::BankTransactionCodes.dk_parts(ret.bank_transaction_code_dk)
    [(parts + [dk[:gvc]]).compact.map { |part| part.label || part.code }.join(" · "),
      (parts + [dk[:gvc]]).compact.map { |part| part.name || part.code }.join(" · ")].join("\n")
  end

  # The input of a return's original on its edit page: the candidates
  # (fin/payment_returns/_original_candidates).
  def payment_return_original_input(f, _row) = render("fin/payment_returns/original_candidates", f: f, ret: f.object)

  # The candidates for the original of the other return `ret`
  # (Fin::ReturnOriginalColumns), each a radio button of the edit form `f`;
  # the linked one chosen, none else.
  def return_original_table_columns(f, ret)
    party = Fin::ReturnOriginals::RULES.dig(ret.return_kind, :party)
    cells = {
      "choose" => ->(c) {
        f.radio_button(:reverses_id, c.id, checked: c.id == ret.reverses_id, class: "form-check-input",
          aria: {label: t("fin.payments.camt_link", id: c.id)})
      },
      "score" => ->(c) { c.score },
      "date" => ->(c) { fin_date(c.transaction.value_date) },
      "amount" => ->(c) { payment_cents((c.transaction.signed_base_amount * 100).round) },
      "code" => ->(c) { payment_short_code(c.transaction) },
      "party" => ->(c) { party ? c.transaction.public_send(:"#{party}_name") : c.transaction.cdtr_name || c.transaction.dbtr_name },
      "matches" => ->(c) { payment_original_matches(ret, c) },
      "description" => ->(c) { c.transaction.description },
      "id" => ->(c) { link_to("##{c.id}", wsjrdp_camt_transaction_path(c.id), data: {turbo_frame: "_top"}) }
    }
    Fin::ReturnOriginalColumns::COLUMNS.map { |col| col.to_table_column(cell: cells.fetch(col.key)) }
  end

  # What else matched besides the amount, and how many days lie between; the
  # tooltip compares every feature, matched or not.
  def payment_original_matches(ret, candidate)
    parts = [t("fin.payments.original_matches.amount")] +
      candidate.matches.map { |key| t("fin.payments.original_matches.#{key}") }
    content_tag(:span, safe_join([content_tag(:span, parts.map { |p| "#{p} ✓" }.join(" "), class: "text-success"),
      t("fin.payments.original_days", count: candidate.days)], " · "),
      title: payment_original_comparison(ret, candidate), class: "payment-original-matches")
  end

  # One line per feature: matched (✓) or not (✗), with both values where they
  # differ.
  def payment_original_comparison(ret, candidate)
    tx = candidate.transaction
    rule = Fin::ReturnOriginals::RULES.fetch(ret.return_kind, {})
    party = rule[:party]
    lines = [t("fin.payments.original_compare.amount",
      amount: payment_cents((tx.signed_base_amount * 100).round))]
    lines << payment_compare_line(:endtoend, ret.endtoend_id, tx.endtoend_id,
      usable: Fin::ReturnOriginals.usable_endtoend?(ret))
    if party
      lines << payment_compare_line(:"#{party}_iban", ret.public_send(:"#{party}_iban"), tx.public_send(:"#{party}_iban"))
      lines << payment_compare_line(:"#{party}_name", ret.public_send(:"#{party}_name"), tx.public_send(:"#{party}_name"),
        same: ->(a, b) { a.to_s.casecmp?(b.to_s) })
    end
    lines << payment_compare_line(:mandate, ret.mandate_id, tx.mandate_id) if rule[:mandate]
    lines << t("fin.payments.original_compare.days", count: candidate.days)
    lines.join("\n")
  end

  def payment_compare_line(key, own, other, usable: own.present?, same: ->(a, b) { a == b })
    label = t("fin.payments.original_compare.labels.#{key}")
    return t("fin.payments.original_compare.missing", label: label) unless usable

    if same.call(own, other)
      t("fin.payments.original_compare.same", label: label, value: own)
    else
      t("fin.payments.original_compare.differs", label: label, own: own, other: other.presence || "–")
    end
  end

  # "ICDT+ESCT · 177": the ISO family and sub-family and the GVC of a bank
  # transaction, the meaning as tooltip.
  def payment_short_code(tx)
    content_tag(:span, [[tx.bank_transaction_family, tx.bank_transaction_sub_family].compact.join("+").presence,
      tx.gvc].compact.join(" · "), class: "font-monospace small", title: payment_codes_tooltip(tx))
  end

  # A bank transaction in one line, linked: "#425 · -519.311,62 € ·
  # ICDT+ESCT · 28.04.2026".
  def payment_transaction_link(tx)
    text = ["##{tx.id}", payment_cents((tx.signed_base_amount * 100).round),
      [tx.bank_transaction_family, tx.bank_transaction_sub_family].compact.join("+").presence,
      fin_date(tx.value_date)].compact.join(" · ")
    link_to(text, wsjrdp_camt_transaction_path(tx), data: {turbo_frame: "_top"})
  end

  def other_return_table_columns
    cells = {
      "date" => ->(ret) { fin_date(ret.booking_date || ret.value_date) },
      "kind" => ->(ret) { t("fin.payments.return_kinds.#{ret.return_kind}") },
      "amount" => ->(ret) { payment_cents(ret.amount_cents) },
      "counterparty" => ->(ret) {
        %w[credit_transfer received_direct_debit].include?(ret.return_kind) ? ret.cdtr_name : ret.dbtr_name
      },
      "reason" => ->(ret) { payment_return_reasons(ret.return_reason, long: true) },
      "code" => ->(ret) {
        content_tag(:span, [[ret.bank_transaction_family, ret.bank_transaction_sub_family].compact.join("+").presence,
          ret.gvc && "GVC #{ret.gvc}"].compact.join(" · "), class: "font-monospace small", title: payment_codes_tooltip(ret))
      },
      "description" => ->(ret) { ret.description },
      "id" => ->(ret) { link_to(ret.id, wsjrdp_camt_transaction_path(ret.id), data: {turbo_frame: "_top"}) }
    }
    Fin::OtherReturnsColumns::COLUMNS.map { |col| col.to_table_column(cell: cells.fetch(col.key)) }
  end

  def direct_debit_payment_info_table_columns
    cells = {
      "order" => ->(info) { payment_order_link(info.payment_initiation_id) },
      "identification" => ->(info) {
        link_to(info.payment_information_identification, direct_debit_payment_info_path(info),
          class: "font-monospace", data: {turbo_frame: "_top"})
      },
      "collection_date" => ->(info) { fin_date(info.requested_collection_date) },
      "sequence" => ->(info) { info.debit_sequence_type },
      "count" => ->(info) { payment_count(info.number_of_transactions) },
      "sum" => ->(info) { payment_cents(info.control_sum_cents) },
      "return_count" => ->(info) { payment_return_count(info.return_count) },
      "returns" => ->(info) { payment_return_sum(info.return_count, info.return_sum_cents) },
      "bank" => ->(info) { payment_info_credit_cell(info) },
      "creditor_id" => ->(info) { content_tag(:span, info.creditor_id, class: "font-monospace") }
    }
    Fin::DirectDebitPaymentInfosColumns::COLUMNS.map { |col| col.to_table_column(cell: cells.fetch(col.key)) }
  end

  # A cell of an order in the Aufträge list: the order's value, and -- for an
  # order of several Sammler -- one small line per Sammler under it
  # (fin/payments/_styles), in the Sammler's order. `same:` names the Sammler
  # attribute that, when equal for all, leaves the order's value alone; `main:
  # false` leaves the order's line empty above the Sammler lines (a value that
  # is the Sammler's own: date, sequence type, bank credit). An empty value is
  # a dash, so the lines of neighbouring cells stay level.
  def payment_order_stack(order, value, same: nil, main: true)
    infos = payment_order_sub_infos[order.id] if respond_to?(:payment_order_sub_infos)
    return value if infos.blank? || (same && infos.map(&same).uniq.size == 1)

    lines = infos.map { |info| content_tag(:div, yield(info).presence || "–", class: "payment-stack-line") }
    head = main ? value.presence || "–" : nil
    safe_join([content_tag(:div, head || "\u00a0", class: "payment-stack-head"), *lines])
  end

  def direct_debit_payment_info_footer(col, totals)
    case col[:key]
    when "count" then payment_count(totals[:count])
    when "sum" then payment_cents(totals[:sum_cents])
    when "return_count" then payment_return_count(totals[:return_count])
    when "returns" then payment_return_sum(totals[:return_count], totals[:return_sum_cents])
    end
  end

  # The Aufträge list filtered on `slots` ([[attribute, operator, value]]),
  # encoded through the list's own schema and param name, as
  # Fin::MossOverviewHelper#moss_foreign_currency_path does: the overview's
  # kind tiles, the Beiträge overview's Lastschriften link and an account's
  # orders.
  def payment_orders_filtered_path(*slots)
    payment_list_filtered_path(payment_orders_path, Fin::PaymentOrdersFilterSchema, Fin::PaymentOrdersController, slots)
  end

  # The Rückläufer and the Einzüge list filtered the same way (the overview's
  # open work and next collection).
  def payment_returns_filtered_path(*slots)
    payment_list_filtered_path(payment_returns_path, Fin::PaymentReturnsFilterSchema, Fin::PaymentReturnsController, slots)
  end

  def direct_debits_filtered_path(*slots)
    payment_list_filtered_path(direct_debits_path, Fin::DirectDebitsFilterSchema, Fin::DirectDebitsController, slots)
  end

  # Each slot a condition of its own, all of them to hold.
  def payment_list_filtered_path(path, schema, controller, slots)
    query = Wsjrdp::Filtering::Query.parse(slots.map { |slot| [slot] })
    rison = Wsjrdp::Filtering::UrlCodec.encode(query, schema: schema.bound)
    param = controller::POLICY.param_name(:filter)
    "#{path}?#{param}=#{Wsjrdp::Filtering::UrlCodec.escape_for_query(rison)}"
  end

  # The payment order of an accounting entry: its own, else -- for the entry
  # of a return, which names none -- the order of the return it was booked
  # for (Fin::PaymentQueries.returns).
  def payment_order_id_of_entry(entry)
    return entry.payment_initiation_id if entry.payment_initiation_id
    return nil unless entry.camt_transaction_id

    Fin::PaymentQueries.returns.where(id: entry.camt_transaction_id).pick(Arel.sql(Fin::PaymentQueries::RETURN_ORDER_SQL))
  end

  # The footer cells: the sums of the whole filtered list under the columns
  # that add up.
  def payment_order_footer(col, totals)
    case col[:key]
    when "count" then payment_count(totals[:count])
    when "sum" then payment_cents(totals[:sum_cents])
    when "pre_notified_count"
      payment_announced_total(payment_count(totals[:pre_notified_count]), totals[:pre_notified_count] == totals[:count])
    when "pre_notified_sum"
      payment_announced_total(payment_cents(totals[:pre_notified_sum_cents]),
        totals[:pre_notified_sum_cents] == totals[:sum_cents])
    when "return_count" then payment_return_count(totals[:return_count])
    when "returns" then payment_return_sum(totals[:return_count], totals[:return_sum_cents])
    end
  end

  # The returns of the orders and the Sammler list in two columns: how many -- a muted 0
  # without any --, and their (negative) sum in red, a muted dash without any;
  # a Sammler's stacked line without any shows the stack's dash in both.
  def payment_return_count(count)
    count.to_i.positive? ? payment_count(count) : content_tag(:span, "0", class: "text-muted")
  end

  def payment_return_sum(count, sum_cents)
    return content_tag(:span, "–", class: "text-muted") unless count.to_i.positive?

    content_tag(:span, payment_cents(sum_cents), class: "text-danger")
  end

  # What an order's pre-notifications announced, in the orange of the finance
  # pages where it differs from what the SEPA file collects; nothing for an
  # order without any (a credit transfer).
  def payment_announced_cell(order, text, same)
    return nil unless order.notice_count.to_i.positive?

    payment_announced_total(text, same)
  end

  def payment_announced_total(text, same)
    return text if same

    content_tag(:span, text, class: "payment-amount-lower", title: t("fin.payments.announced_differs"))
  end

  # The lines under a debits table: how many, what was announced, how much of
  # it was collected, skipped or is still open, and the returns. Parts without
  # debits are left out.
  def direct_debit_totals_lines(totals)
    scope = "fin.payments.debit_totals"
    parts = %i[collected skipped open].filter_map do |key|
      next unless totals[:"#{key}_count"].positive?

      t("#{scope}.#{key}", amount: payment_cents(totals[:"#{key}_cents"]), count: payment_count(totals[:"#{key}_count"]))
    end
    lines = [t("#{scope}.announced", debits: t("fin.payments.debits_shown", count: totals[:count]),
      amount: payment_cents(totals[:announced_cents]))]
    lines << parts.join(" · ") if parts.any?
    if totals[:return_count].positive?
      lines << t("#{scope}.returns", amount: payment_cents(totals[:return_sum_cents]),
        count: payment_count(totals[:return_count]))
    end
    lines
  end

  # The amount a debit collects (fin/payments/_styles): the collected one,
  # nothing for a skipped one, the planned one while it is only announced.
  # Where it differs from the announced amount, that one stands struck through
  # in front, and the colour tells the case: orange less, red more, blue still
  # planned, muted skipped. The tooltip names announced, actual and the
  # difference.
  def payment_debit_amount_cell(debit)
    announced = debit.pre_notified_amount_cents
    actual = payment_debit_actual_cents(debit)
    return payment_cents(actual) if announced.nil? || announced == actual

    kind = payment_debit_amount_kind(debit, announced, actual)
    parts = [content_tag(:s, payment_cents(announced), class: "payment-amount-announced"),
      content_tag(:span, payment_cents(actual))]
    parts << icon(:"exclamation-triangle") if kind == "higher"
    content_tag(:span, safe_join(parts, " "), class: ["payment-amount-differs", "payment-amount-#{kind}"],
      title: payment_debit_amount_tooltip(debit, announced, actual))
  end

  def payment_debit_actual_cents(debit)
    (debit.payment_status == "skipped") ? 0 : debit.amount_cents
  end

  def payment_debit_amount_kind(debit, announced, actual)
    return "skipped" if debit.payment_status == "skipped"
    return "planned" if debit.payment_status == Fin::DebitEditing::PRE_NOTIFIED

    (actual > announced) ? "higher" : "lower"
  end

  # Announced, actual and -- unless the actual is nothing -- the difference,
  # one per line.
  def payment_debit_amount_tooltip(debit, announced, actual)
    scope = "fin.payments.debit_amount_tooltip"
    actual_key = (debit.payment_status == Fin::DebitEditing::PRE_NOTIFIED) ? "planned" : "collected"
    lines = [t("#{scope}.announced", amount: payment_cents(announced)),
      t("#{scope}.#{actual_key}", amount: payment_cents(actual))]
    unless actual.zero?
      diff = actual - announced
      lines << t("#{scope}.difference", amount: "#{"+" if diff.positive?}#{payment_cents(diff)}")
    end
    lines.join("\n")
  end

  def payment_return_footer(col, totals)
    payment_cents(totals[:sum_cents]) if col[:key] == "amount"
  end

  # The kind: its icon and word; a conflicting or unknown kind in the
  # warning colour, with what it means as tooltip.
  def payment_kind_cell(kind)
    label = t("fin.payments.kinds.#{kind}")
    warn = [WsjrdpPaymentInitiation::CONFLICT, WsjrdpPaymentInitiation::UNKNOWN].include?(kind)
    content_tag(:span, safe_join([icon(KIND_ICONS.fetch(kind, :question)), label], " "),
      class: ("text-warning" if warn), title: t("fin.payments.kind_hints.#{kind}"))
  end

  def payment_kind_label(kind) = t("fin.payments.kinds.#{kind}")

  # The order's account, linked to its page; without one the initiating
  # party's IBAN, muted.
  def payment_account_cell(order)
    if order.fin_account_id
      link_to(order.fin_account_short_name.presence || order.fin_account_identification,
        wsjrdp_fin_account_path(order.fin_account_id), data: {turbo_frame: "_top"})
    else
      content_tag(:span, order.initiating_party_iban, class: "text-muted font-monospace",
        title: t("fin.payments.no_account"))
    end
  end

  def payment_order_link(id)
    id && link_to("##{id}", payment_order_path(id), data: {turbo_frame: "_top"})
  end

  def payment_date_range(first, last)
    return nil unless first

    (last && last != first) ? "#{fin_date(first)} – #{fin_date(last)}" : fin_date(first)
  end

  def payment_sequences(types)
    return nil if types.blank?

    safe_join(types.split.map { |type| content_tag(:span, type, class: "badge text-bg-light border me-1 payment-seq-badge") })
  end

  def payment_count(count) = count && number_with_delimiter(count, delimiter: ".")

  def payment_cents(cents) = cents && fin_money(cents.to_d / 100)

  # A figure with the announced one beside it, muted and light in brackets
  # -- "(vorab informiert: …)" (fin/payments/_styles); the figure alone
  # without an announced one.
  def payment_with_announced(text, announced)
    return text if announced.nil?

    note = content_tag(:span, "(#{t("fin.payments.pre_notified_note", amount: announced)})",
      class: "payment-pre-notified text-muted fw-light")
    content_tag(:span, safe_join([content_tag(:span, text), note]), class: "payment-amount-with-note")
  end

  # A count and, a gap apart, its sum ("Σ …"); where the sum is made of more
  # than one amount, below it small and muted its amounts, the most frequent
  # first ("k× amount · …"; `amounts`: [cents, count] pairs in that order).
  # The first `limit` show; the rest wait behind a "mehr" button that shows
  # `limit` more per click (fin/payments/_styles). A count of 0 stands alone.
  def payment_count_with_breakdown(count, sum_html, amounts, limit: BREAKDOWN_LIMIT)
    return payment_count(count) unless count.positive?

    line = content_tag(:span, safe_join([content_tag(:span, payment_count(count)), sum_html]),
      class: "payment-amount-with-note")
    return line unless amounts.size > 1

    safe_join([line, payment_breakdown(amounts, limit)])
  end

  def payment_breakdown(amounts, limit)
    items = amounts.each_with_index.map do |(cents, n), i|
      content_tag(:span, "#{" · " if i.positive?}#{payment_count(n)}×#{Fin::MoneyHelper::NBSP}#{fin_money_compact(cents.to_d / 100)}",
        class: "payment-breakdown-item", hidden: i >= limit)
    end
    if amounts.size > limit
      items << content_tag(:button, t("fin.payments.breakdown_more"), type: "button",
        class: "payment-breakdown-more btn btn-link btn-sm p-0 align-baseline")
    end
    content_tag(:div, safe_join(items), class: "payment-breakdown text-muted small", data: {step: limit})
  end

  # The returns of an order or a debit: how many and their (negative) sum;
  # empty without any.
  def payment_returns_cell(count, sum_cents)
    return nil unless count.to_i.positive?

    content_tag(:span, safe_join([content_tag(:span, "#{payment_count(count)} ×", class: "text-muted small me-1"),
      payment_cents(sum_cents)]), class: "text-danger")
  end

  # A debit's return: date and reason codes in red, the reasons' wording as
  # tooltip.
  def payment_debit_return_cell(debit)
    return nil unless debit.return_count.to_i.positive?

    content_tag(:span, safe_join([fin_date(debit.return_date), payment_return_reasons(debit.return_reasons)].compact,
      " "), class: "text-danger")
  end

  # Reason codes ("MS03 MD06"), each with its wording as tooltip; `long:`
  # writes the wording beside the code.
  def payment_return_reasons(codes, long: false)
    return nil if codes.blank?

    safe_join(codes.split.map do |code|
      label = Fin::ReturnReasons.label(code)
      text = (long && label) ? "#{code} – #{label}" : code
      content_tag(:span, text, title: label, class: "payment-return-reason")
    end, ", ")
  end

  # A return's debit: its collection date, linked to it, with a muted mark
  # where the return does not link it but was matched (end-to-end id or
  # mandate); not assignable in the warning colour.
  def payment_return_debit_cell(ret)
    return payment_return_unassigned unless ret.notice_id

    payment_return_debit_link(ret, fin_date(ret.notice_collection_date) || "##{ret.notice_id}")
  end

  def payment_return_debit_link(ret, text)
    link = link_to(text, direct_debit_path(ret.notice_id), data: {turbo_frame: "_top"})
    mark = payment_return_match_mark(ret.notice_matched_by)
    mark ? safe_join([link, mark], " ") : link
  end

  # How an unlinked return was matched, muted; nil for a linked one.
  def payment_return_match_mark(matched_by)
    return nil if matched_by.nil? || matched_by == Fin::PaymentQueries::MATCHED_BY_LINK

    content_tag(:span, t("fin.payments.return_matched_by.#{matched_by}"), class: "text-muted small",
      title: t("fin.payments.return_matched_by_hints.#{matched_by}"))
  end

  # The badge colour of a return's processing status
  # (Settings.return_debit_status): open in yellow, paid in green, written off
  # in grey.
  RETURN_STATUS_BADGES = {
    "in_review" => "text-bg-warning",
    "planned" => "text-bg-info",
    "paid" => "text-bg-success",
    "partially_depreciated" => "text-bg-light border",
    "depreciated" => "text-bg-secondary"
  }.freeze

  # A return's processing status as a coloured badge, centred in its cell.
  def payment_return_status_cell(ret)
    badge = RETURN_STATUS_BADGES[ret.return_status]
    label = ret.return_status_display
    content_tag(:div, badge ? content_tag(:span, label, class: "badge fw-normal #{badge}") : label, class: "text-center")
  end

  def payment_return_unassigned
    content_tag(:span, safe_join([icon(:"exclamation-triangle"), t("fin.payments.unassigned")], " "),
      class: "text-warning", title: t("fin.payments.unassigned_hint"))
  end

  # The bank's collective credit of an order -- of its Sammler -- once its
  # SEPA file went to the bank (CREDIT_DUE_STATUSES) and it collects; nothing
  # for a credit transfer order.
  def payment_order_credit_cell(order)
    payment_credit_cell(order, due: order.direct_debit? && CREDIT_DUE_STATUSES.include?(order.status))
  end

  def payment_info_credit_cell(info)
    payment_credit_cell(info, due: CREDIT_DUE_STATUSES.include?(info.order_status))
  end

  # The credit as "#id value-date", linked to the (first) bank transaction,
  # with the count where there are several -- as large in a Sammler's stacked
  # line as in a row of its own (fin/payments/_styles); in the warning colour
  # where the credits do not add up to the control sum, or where a due one is
  # missing.
  def payment_credit_cell(record, due:)
    if record.credit_count.to_i.zero?
      return payment_mark(nil) unless due

      return content_tag(:span, safe_join([icon(:"exclamation-triangle"), t("fin.payments.no_credit")], " "),
        class: "text-warning", title: t("fin.payments.no_credit_hint"))
    end

    text = "##{record.credit_id} #{fin_date(record.credit_date)}"
    text = "#{text} (#{record.credit_count} ×)" if record.credit_count.to_i > 1
    link = link_to(text, wsjrdp_camt_transaction_path(record.credit_id), class: "payment-credit-link",
      data: {turbo_frame: "_top"})
    return link if record.credit_sum_cents.to_i == record.control_sum_cents.to_i

    content_tag(:span, safe_join([icon(:"exclamation-triangle"), link], " "), class: "text-warning",
      title: t("fin.payments.credit_differs", credit: payment_cents(record.credit_sum_cents),
        control: payment_cents(record.control_sum_cents)))
  end

  # Every bank credit of an order, linked to the bank transaction: "#id
  # amount sequence-type value-date", side by side where there is room, a
  # line break only between two credits. Without credits, and
  # where they do not add up to the control sum, as #payment_order_credit_cell
  # has it.
  def payment_order_credits_list(order)
    return payment_order_credit_cell(order) if order.credit_count.to_i.zero?

    lines = Fin::PaymentQueries.order_credits(order.id).map do |credit|
      text = ["##{credit.id}", fin_money_compact(credit.amount_cents.to_d / 100), credit.debit_sequence_type,
        fin_date(credit.value_date)].compact.join(" ")
      link_to(text, wsjrdp_camt_transaction_path(credit.id), class: "text-nowrap", data: {turbo_frame: "_top"})
    end
    list = content_tag(:span, safe_join(lines, " · "))
    return list if order.credit_sum_cents.to_i == order.control_sum_cents.to_i

    content_tag(:div, safe_join([icon(:"exclamation-triangle"), list], " "), class: "text-warning d-flex gap-1",
      title: t("fin.payments.credit_differs", credit: payment_cents(order.credit_sum_cents),
        control: payment_cents(order.control_sum_cents)))
  end

  # The accounting entry booked for a return, a tick linked to it; none in the
  # warning colour -- the return still has to be booked on the person.
  def payment_return_entry_cell(entry_id)
    mark = if entry_id
      payment_entry_mark(entry_id)
    else
      content_tag(:span, icon(:"exclamation-triangle"), class: "text-warning", title: t("fin.payments.no_return_entry"))
    end
    content_tag(:div, mark, class: "text-center")
  end

  # The announced amount, marked where it differs from the collected one.
  def payment_pre_notified_cell(debit)
    debit.pre_notified_amount_cents && payment_pre_notified_note(debit, label: false)
  end

  # The amount a debit's pre-notification announced (fin/payments/_styles):
  # orange and half bold where it differs from the collected one, muted and
  # light where it is the same; `label:` writes "vorab informiert:" in front.
  def payment_pre_notified_note(debit, label: true)
    cents = debit.pre_notified_amount_cents
    differs = cents != debit.amount_cents
    text = payment_cents(cents)
    text = t("fin.payments.pre_notified_note", amount: text) if label
    content_tag(:span, text,
      class: ["payment-pre-notified", differs ? "payment-pre-notified-differs" : "text-muted fw-light"],
      title: (differs ? t("fin.payments.amount_differs") : t("fin.payments.amount_as_announced")))
  end

  def payment_entry_mark(entry_id)
    return payment_mark(nil) unless entry_id

    link_to("✓", accounting_entry_path(entry_id), class: "text-muted text-decoration-none",
      title: t("fin.payments.entry_link", id: entry_id), data: {turbo_frame: "_top"})
  end

  # A quiet tick for what is there, a muted dash for what is not.
  def payment_mark(present)
    present ? content_tag(:span, "✓", class: "text-muted") : content_tag(:span, "–", class: "text-muted")
  end

  # The label of a debit: "Vorabankündigung Einzug #id" while it is only
  # announced (pre_notified), "Einzug #id" once it is in a SEPA file or
  # skipped.
  def payment_debit_label(debit)
    key = (debit.payment_status == Fin::DebitEditing::PRE_NOTIFIED) ? "debit_notice_label" : "debit_label"
    t("fin.payments.#{key}", id: debit.id)
  end

  # A payment role ("RegularPayer::Group::Unit::Member") as its contingent
  # role and payer kind -- "YP · Ratenzahler" -- with the stored value as
  # tooltip (Fin::PaymentRoles).
  def payment_role_cell(role)
    role.presence && content_tag(:span, Fin::PaymentRoles.label(role), title: role)
  end

  def payment_status_label(status)
    status && t("fin.payments.statuses.#{status}", default: status.to_s)
  end
end
