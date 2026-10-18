# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is payment_info of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The Zahlungsverkehr area (doc/fin/payments.md): the overview, the orders,
# an order's page, the debits and the returns -- what they show, and who sees
# the person-level ones. All names, numbers and dates are invented.
describe "Zahlungsverkehr", type: :request do
  let(:accountant) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }
  let(:reader) { Fabricate(Group::Root::FinanceReader.name.to_sym, group: groups(:root)).person }
  let(:person) { people(:yp_a_1) }

  let!(:account) do
    WsjrdpFinAccount.create!(short_name: "Beispielkonto", account_identification: "DE02 1203 0000 0000 2020 51",
      opening_balance_cents: 0, opening_balance_currency: "EUR", opening_balance_date: Date.new(2026, 1, 1))
  end
  let!(:debit_order) do
    WsjrdpPaymentInitiation.create!(status: "xml_generated", sepa_schema: "pain.008.001.08",
      message_identification: "MSG-DD-1", number_of_transactions: 2, control_sum_cents: 30_000,
      initiating_party_iban: "DE02120300000000202051")
  end
  let!(:transfer_order) do
    WsjrdpPaymentInitiation.create!(status: "xml_generated", sepa_schema: "pain.001.001.09",
      message_identification: "MSG-CT-1", number_of_transactions: 1, control_sum_cents: 5_000)
  end
  let!(:payment_info) do
    WsjrdpDirectDebitPaymentInfo.create!(payment_initiation: debit_order, payment_information_identification: "PMT-1",
      debit_sequence_type: "RCUR", requested_collection_date: Date.new(2026, 5, 5), number_of_transactions: 2,
      control_sum_cents: 30_000)
  end
  let!(:returned_debit) { debit("E2E-1", 20_000) }
  let!(:paid_debit) { debit("E2E-2", 10_000, subject: people(:yp_a_2)) }
  let!(:returned) { camt_return(-200, endtoend_id: "E2E-1", return_reason: "MD06") }
  let!(:return_entry) do
    entry(-20_000, endtoend_id: "E2E-1", return_reason: "MD06", camt_transaction_id: returned.id)
  end
  let!(:unassigned_return) { camt_return(-75, endtoend_id: "E2E-UNKNOWN", return_reason: "MS03") }

  def debit(endtoend_id, cents, subject: person)
    WsjrdpDirectDebitPreNotification.create!(payment_initiation: debit_order, direct_debit_payment_info: payment_info,
      subject: subject, author: subject, amount_cents: cents, pre_notified_amount_cents: cents,
      description: "Beitrag", dbtr_name: "Muster", dbtr_iban: "DE02120300000000202051",
      debit_sequence_type: "RCUR", collection_date: Date.new(2026, 5, 5), payment_status: "xml_generated",
      endtoend_id: endtoend_id)
  end

  def entry(cents, **attrs)
    AccountingEntry.create!(subject: person, author: person, amount_cents: cents, description: "Rücklastschrift",
      value_date: Date.new(2026, 5, 12), **attrs)
  end

  # A return as the bank statement holds it.
  def camt_return(amount, **attrs)
    WsjrdpCamtTransaction.create!(fin_account: account, camt_type: "CAMT052",
      account_identification: account.account_identification, account_servicer_reference: SecureRandom.hex(8),
      credit_debit_indication: "DBIT",
      signed_base_amount: amount, base_currency: "EUR", value_date: Date.new(2026, 5, 5),
      booking_date: Date.new(2026, 5, 12), description: "Retoure", subject: person, **attrs)
  end

  # The bank's collective credit of a Sammler.
  def camt_credit(amount, info)
    WsjrdpCamtTransaction.create!(fin_account: account, camt_type: "CAMT052",
      account_identification: account.account_identification, account_servicer_reference: SecureRandom.hex(8),
      credit_debit_indication: "CRDT", bank_transaction_code: "PMNT+IDDT+ESDD",
      signed_base_amount: amount, base_currency: "EUR", value_date: Date.new(2026, 5, 5),
      booking_date: Date.new(2026, 5, 5), description: "Basislastschrift", direct_debit_payment_info: info,
      payment_initiation: info.payment_initiation)
  end

  def html = Capybara.string(response.body)

  # The ids of a table's rows (the footer row left out).
  def rows(prefix) = html.all("tr.exp-row td.#{prefix}-id").map { |cell| cell.text.strip }

  describe "WsjrdpPaymentInitiation#kind" do
    it "says in Ruby what kind_sql says in SQL" do
      conflict = WsjrdpPaymentInitiation.create!(sepa_schema: "pain.001.001.09")
      WsjrdpDirectDebitPaymentInfo.create!(payment_initiation: conflict)
      unknown = WsjrdpPaymentInitiation.create!
      orders = [debit_order, transfer_order, conflict, unknown]

      sql = WsjrdpPaymentInitiation.where(id: orders).pluck(:id, Arel.sql(WsjrdpPaymentInitiation.kind_sql)).to_h
      expect(orders.map { |order| [order.reload.kind, sql[order.id]] }).to eq(
        [%w[direct_debit direct_debit], %w[credit_transfer credit_transfer], %w[conflict conflict],
          %w[unknown unknown]]
      )
    end

    it "takes an order with direct debit Sammler but no schema for a direct debit" do
      order = WsjrdpPaymentInitiation.create!
      WsjrdpDirectDebitPaymentInfo.create!(payment_initiation: order)

      expect(order.kind).to eq("direct_debit")
    end
  end

  describe "Fin::PaymentQueries" do
    it "assigns a return to its debit and order by the end-to-end id" do
      orders = Fin::PaymentQueries.orders.where(id: [debit_order, transfer_order]).index_by(&:id)
      expect(orders[debit_order.id]).to have_attributes(kind: "direct_debit", return_count: 1,
        return_sum_cents: -20_000, sequence_types: "RCUR", fin_account_id: account.id)
      expect(orders[transfer_order.id]).to have_attributes(kind: "credit_transfer", return_count: 0,
        fin_account_id: nil)

      returns = Fin::PaymentQueries.returns.where(id: [returned, unassigned_return]).index_by(&:id)
      expect(returns[returned.id]).to have_attributes(notice_id: returned_debit.id, notice_matched_by: "endtoend",
        order_id: debit_order.id, info_id: payment_info.id, return_entry_id: return_entry.id, amount_cents: -20_000)
      expect(returns[unassigned_return.id]).to have_attributes(notice_id: nil, order_id: nil, return_entry_id: nil)
    end

    it "finds the debit by the mandate where the bank sent an end-to-end id of its own" do
      paid_debit.update!(mandate_id: "wsjrdp-test-2")
      by_mandate = camt_return(-100, endtoend_id: "2512181044-0000002", mandate_id: "wsjrdp-test-2",
        return_reason: "MS03", value_date: Date.new(2026, 5, 8))
      too_late = camt_return(-100, endtoend_id: "2512181044-0000003", mandate_id: "wsjrdp-test-2",
        return_reason: "MS03", value_date: Date.new(2026, 5, 20))

      returns = Fin::PaymentQueries.returns.where(id: [by_mandate, too_late]).index_by(&:id)
      expect(returns[by_mandate.id]).to have_attributes(notice_id: paid_debit.id, notice_matched_by: "mandate",
        order_id: debit_order.id)
      expect(returns[too_late.id]).to have_attributes(notice_id: nil, order_id: nil)
      expect(Fin::PaymentQueries.debits.find(paid_debit.id)).to have_attributes(return_count: 1,
        return_sum_cents: -10_000)
    end

    it "takes the debit a return links over any it would match" do
      returned.update!(direct_debit_pre_notification: paid_debit)

      ret = Fin::PaymentQueries.returns.find(returned.id)
      expect(ret).to have_attributes(notice_id: paid_debit.id, notice_matched_by: "link")
      expect(Fin::PaymentQueries.debits.find(returned_debit.id)).to have_attributes(return_count: 0)
      expect(paid_debit.return_camt_transactions).to eq([returned])
      expect(paid_debit.collection_camt_transactions).to be_empty
    end

    it "sums the bank's collective credits of a Sammler and its order" do
      expect(Fin::PaymentQueries.payment_info(payment_info.id)).to have_attributes(credit_count: 0,
        order_status: "xml_generated")
      credit = camt_credit(300, payment_info)

      expect(Fin::PaymentQueries.payment_info(payment_info.id)).to have_attributes(credit_count: 1,
        credit_sum_cents: 30_000, credit_id: credit.id, credit_date: Date.new(2026, 5, 5))
      expect(Fin::PaymentQueries.orders.find(debit_order.id)).to have_attributes(credit_count: 1,
        credit_sum_cents: 30_000)
      expect(payment_info.camt_transactions).to eq([credit])
    end

    it "takes the bank statement, not the accounting entries, as the record of a return" do
      entry(-3_000, endtoend_id: "E2E-2", return_reason: "MS03")

      expect(Fin::PaymentQueries.returns.count(:all)).to eq(2)
      expect(Fin::PaymentQueries.debits.find(paid_debit.id)).to have_attributes(return_count: 0)
    end

    it "sums a whole list" do
      totals = Fin::PaymentQueries.order_totals(Fin::PaymentQueries.orders.where(id: [debit_order, transfer_order]))
      expect(totals).to eq(count: 3, sum_cents: 35_000, return_count: 1, return_sum_cents: -20_000)
    end
  end

  context "for the write tier" do
    before { sign_in(accountant) }

    it "shows the overview with the orders by kind, the debits and the returns" do
      get fin_payments_path

      expect(response).to have_http_status(:ok)
      expect(html).to have_css("ul.nav-sub li", text: I18n.t("fin.tabs.direct_debits"))
      expect(html).to have_css("#main a", text: I18n.t("fin.payments.tiles.debits"))
      expect(html).to have_css("#main a", text: I18n.t("fin.payments.tiles.unassigned"))
    end

    it "lists the orders with kind, account, returns and sums" do
      get payment_orders_path

      expect(response).to have_http_status(:ok)
      row = html.find("tr.exp-row", text: "MSG-DD-1", match: :first) if html.has_css?("tr.exp-row", text: "MSG-DD-1")
      row ||= html.all("tr.exp-row").find { |tr| tr.has_css?("td.pocol-id", text: debit_order.id.to_s) }
      expect(row).to have_css("td.pocol-kind", text: "Lastschrift")
      expect(row).to have_css("td.pocol-returns .text-danger", text: "1 ×")
      expect(row).to have_css("td.pocol-bank .text-warning", text: I18n.t("fin.payments.no_credit"))
      expect(html).to have_css("tfoot td.pocol-count, tr.exp-footer td.pocol-count", text: /\d/)

      get payment_order_path(debit_order)
      expect(html).to have_link("Beispielkonto", href: wsjrdp_fin_account_path(account))
    end

    it "shows the bank's credit of a Sammler and its order, warned where it differs from the control sum" do
      credit = camt_credit(250, payment_info)

      get direct_debit_payment_infos_path
      row = html.all("tr.exp-row").find { |tr| tr.has_css?("td.dpcol-order", text: "##{debit_order.id}") }
      expect(row).to have_css("td.dpcol-bank .text-warning a[href='#{wsjrdp_camt_transaction_path(credit)}']",
        text: "05.05.2026")

      credit.update!(signed_base_amount: 300)
      get direct_debit_payment_info_path(payment_info)
      expect(html).to have_link("05.05.2026", href: wsjrdp_camt_transaction_path(credit))
      expect(html).to have_no_css(".fin-detail-list .text-warning")

      get payment_order_path(debit_order)
      expect(html).to have_link("05.05.2026", href: wsjrdp_camt_transaction_path(credit))
    end

    it "filters the orders on their kind" do
      get payment_orders_path
      get controller.view_context.payment_orders_filtered_path(["kind", "in", "credit_transfer"])

      expect(rows("pocol")).to eq([transfer_order.id.to_s])
    end

    it "shows an order's page with its Sammler and its debits" do
      get payment_order_path(debit_order)

      expect(response).to have_http_status(:ok)
      expect(html).to have_css("td.dpcol-count", text: "2")
      expect(html).to have_no_css("td.dpcol-identification")
      expect(response.body).to include(direct_debit_payment_info_path(payment_info))
      expect(html).to have_css("tr.exp-row td.ddcol-person", count: 2)
      expect(html).to have_css("td.ddcol-return .text-danger", text: "MD06")
      expect(html).to have_no_css("td.ddcol-order")
    end

    it "shows the figures of each Sammler under an order's own, without sub-rows or links" do
      second = WsjrdpDirectDebitPaymentInfo.create!(payment_initiation: debit_order,
        payment_information_identification: "PMT-2", debit_sequence_type: "FRST",
        requested_collection_date: Date.new(2026, 5, 6), number_of_transactions: 1, control_sum_cents: 4_000)

      get payment_orders_path

      row = html.all("tr.exp-row").find { |tr| tr.has_css?("td.pocol-id", text: debit_order.id.to_s) }
      expect(row.all("td.pocol-count .payment-stack-line").map { |line| line.text.strip }).to eq(%w[2 1])
      expect(row.find("td.pocol-count .payment-stack-head").text.strip).to eq("2")
      expect(row.all("td.pocol-sum .payment-stack-line").last.text).to include("40,00")
      expect(row.all("td.pocol-sequence .payment-stack-line").size).to eq(2)
      expect(row.all("td.pocol-execution_date .payment-stack-line").map { |line| line.text.strip })
        .to eq(%w[05.05.2026 06.05.2026])
      expect(html).to have_no_css("tr.exp-sub-row")
      expect(html).to have_no_link(href: direct_debit_payment_info_path(second))
      expect(html).to have_no_css("th.pocol-created_at")
      expect(html).to have_no_css("th.pocol-account")
      expect(html).to have_css("th.pocol-sum", text: "Betrag")
    end

    it "shows a Sammler's page with its creditor, returns and only its debits" do
      other = WsjrdpDirectDebitPaymentInfo.create!(payment_initiation: debit_order,
        payment_information_identification: "PMT-2", debit_sequence_type: "FRST")
      paid_debit.update!(direct_debit_payment_info: other)

      get direct_debit_payment_info_path(payment_info)

      expect(response).to have_http_status(:ok)
      expect(html).to have_text("PMT-1")
      expect(html).to have_css(".text-danger", text: "1 ×")
      expect(html).to have_css("tr.exp-row td.ddcol-person", count: 1)
      expect(html).to have_link(href: payment_order_path(debit_order))
    end

    it "takes a debit that names no Sammler by the Sammler's order, sequence type and collection date" do
      returned_debit.update!(direct_debit_payment_info: nil)

      get direct_debit_payment_info_path(payment_info)

      expect(html).to have_css("tr.exp-row td.ddcol-person", count: 2)
      expect(html).to have_css(".text-danger", text: "1 ×")
    end

    it "warns where the collection entry books another amount, and prefixes the people in the lists" do
      AccountingEntry.create!(subject: person, author: person, amount_cents: 15_000, description: "Einzug",
        direct_debit_pre_notification: returned_debit)

      get direct_debit_path(returned_debit)
      expect(html).to have_css(".fin-detail-list dd .payment-pre-notified-differs",
        text: /Die Beitragsbuchung bucht 150,00.€, der Einzug 200,00.€\./)

      get direct_debits_path
      expect(html).to have_css("tr.exp-row td.ddcol-person span.text-muted.fw-light",
        text: "#{person.short_payment_role} #{person.id}")
      get payment_returns_path
      expect(html).to have_css("tr.exp-row td.prcol-person span.text-muted.fw-light",
        text: "#{person.short_payment_role} #{person.id}")
    end

    it "lists the Sammler with their order, returns and sums" do
      get direct_debit_payment_infos_path

      expect(response).to have_http_status(:ok)
      expect(html).to have_css("ul.nav-sub li.active", text: I18n.t("fin.tabs.direct_debit_payment_infos"))
      row = html.all("tr.exp-row").find { |tr| tr.has_css?("td.dpcol-order", text: "##{debit_order.id}") }
      expect(row).to have_css("td.dpcol-order a", text: "##{debit_order.id}")
      expect(row).to have_css("td.dpcol-returns .text-danger", text: "1 ×")
      expect(html).to have_no_css("th.dpcol-identification").and have_no_css("th.dpcol-creditor_id")

      get direct_debit_payment_info_path(payment_info)
      expect(html).to have_css("ul.nav-sub li.active", text: I18n.t("fin.tabs.direct_debit_payment_infos"))
    end

    it "shows only head and Sammler in the list's row" do
      get payment_order_path(debit_order), headers: {"Turbo-Frame" => "po-#{debit_order.id}"}

      expect(html).to have_css("td.dpcol-count", text: "2")
      expect(html).to have_no_css("td.ddcol-person")
    end

    it "lists the debits and opens one" do
      get direct_debits_path
      expect(response).to have_http_status(:ok)
      expect(html).to have_css("td.ddcol-order a", text: "##{debit_order.id}")

      expect(html).to have_no_css("th.ddcol-role")

      returned_debit.update!(email_to: ["eltern@example.com", "Erika Mustermann <erika@example.com>"])
      get direct_debit_path(returned_debit)
      expect(response).to have_http_status(:ok)
      expect(html).to have_css(".fin-detail-list dd .text-danger", text: "MD06")
      expect(html).to have_css(".fin-detail-list dd", text: "eltern@example.com, Erika Mustermann <erika@example.com>")
      expect(html).to have_css(".fin-detail-list dd a[href='mailto:eltern@example.com']")
      expect(html).to have_css(".fin-detail-list dd a[href='mailto:erika@example.com']", text: "Erika Mustermann")

      expect(html).to have_css("h1", text: "Einzug ##{returned_debit.id}")
      expect(html).to have_no_text("Vorabankündigung Einzug")
      AccountingEntry.create!(subject: person, author: person, amount_cents: 20_000, description: "Einzug",
        direct_debit_pre_notification: returned_debit)
      returned_debit.update!(payment_status: "pre_notified")
      get direct_debit_path(returned_debit)
      expect(html).to have_css("h1", text: "Vorabankündigung Einzug ##{returned_debit.id}")
      expect(html).to have_link("Zurück zu Einzüge", href: direct_debits_path)
      returned_debit.update!(payment_status: "xml_generated")
      get direct_debit_path(returned_debit)
      expect(html.all(".fin-detail-list dt").map { |dt| dt.text.strip }.first(9))
        .to eq(["Person", "Betrag", "Fälligkeit", "Status", "Rücklastschrift", "Auftrag", "Sammler",
          "Beitragsbuchung", "Auch unter"])
      expect(html).to have_link(href: accounting_entry_path(AccountingEntry.last))
      expect(html).to have_no_css(".fin-detail-list .payment-pre-notified-differs", text: "Beitragsbuchung bucht")
      expect(html).to have_css(".fin-detail-list dd", text: "05.05.2026 · RCUR")
      returned_debit.update!(mandate_id: "wsjrdp123", mandate_date: Date.new(2025, 10, 9))
      get direct_debit_path(returned_debit)
      mandate = html.all(".fin-detail-list .row").find { |row| row.find("dt").text.strip == "Mandat" }
      expect(mandate.find("dd").text.strip).to eq("wsjrdp123 vom 09.10.2025")
      expect(html).to have_css(".fin-detail-list dt", text: "Gläubiger-ID")
      expect(html).to have_no_css(".fin-detail-list dt", text: "Mandatsreferenz")
      expect(html).to have_css(".fin-detail-list dd span.text-muted.fw-light", text: "xml_generated")
      expect(html).to have_css(".fin-detail-list dd", text: "#{person.short_payment_role} #{person.id} #{person.short_full_name_with_nickname}")
      expect(html).to have_css(".fin-detail-list dd span.text-muted.fw-light", text: "#{person.short_payment_role} #{person.id}")
      expect(html).to have_css(".fin-detail-list dd .payment-pre-notified.text-muted.fw-light",
        text: "vorab informiert: 200,00")

      returned_debit.update!(pre_notified_amount_cents: 25_000)
      get direct_debit_path(returned_debit)
      expect(html).to have_css(".fin-detail-list dd", text: /200,00.*vorab informiert: 250,00/)
      expect(html).to have_css(".payment-pre-notified.payment-pre-notified-differs")
      expect(html).to have_no_css(".fin-detail-list dt", text: "Vorab informierter Betrag")

      returned_debit.update!(payment_role: "RegularPayer::Group::Unit::Member")
      get direct_debit_path(returned_debit)
      expect(html).to have_css(".fin-detail-list dd span[title='RegularPayer::Group::Unit::Member']",
        text: "YP · Ratenzahler")
    end

    it "lists the returns and marks the one that cannot be assigned" do
      get payment_returns_path

      expect(response).to have_http_status(:ok)
      expect(html).to have_css("td.prcol-debit a", text: "05.05.2026")
      expect(html).to have_css("td.prcol-debit .text-warning", text: I18n.t("fin.payments.unassigned"))
      expect(html).to have_css("td.prcol-reason span[title]", text: "MD06")
      expect(html).to have_css("td.prcol-entry a[href='#{accounting_entry_path(return_entry)}']")
      expect(html).to have_css("td.prcol-entry .text-warning[title='#{I18n.t("fin.payments.no_return_entry")}']")
      expect(html).to have_css("td.prcol-debit", text: I18n.t("fin.payments.return_matched_by.endtoend"))

      returned.update!(direct_debit_pre_notification: returned_debit)
      get payment_returns_path
      expect(html).to have_css("td.prcol-debit a", text: "05.05.2026")
      expect(html).to have_no_css("td.prcol-debit", text: I18n.t("fin.payments.return_matched_by.endtoend"))

      get payment_return_path(unassigned_return)
      expect(response).to have_http_status(:ok)
      expect(html).to have_css(".fin-detail-list .text-warning[title='#{I18n.t("fin.payments.unassigned_hint")}']",
        text: I18n.t("fin.payments.unassigned"))
      expect(html).to have_css(".fin-detail-list .text-warning", text: I18n.t("fin.payments.no_return_entry"))
        .and have_link(href: wsjrdp_camt_transaction_path(unassigned_return))

      get payment_return_path(returned)
      expect(html).to have_link(I18n.t("fin.payments.entry_link", id: return_entry.id),
        href: accounting_entry_path(return_entry))
        .and have_link(I18n.t("fin.payments.payment_info_label", id: payment_info.id))
    end
  end

  describe "the edit page of a debit" do
    let(:auditor) do
      Fabricate(Group::Extern::FinanceAuditor.name.to_sym,
        group: Group::Extern.create!(name: "Extern", parent: groups(:root))).person
    end
    let(:params) { {wsjrdp_direct_debit_pre_notification: changes} }

    # The fields of the debit's form (the page's search field left out).
    def inputs
      html.all("[name^='wsjrdp_direct_debit_pre_notification[']:not([type=hidden])")
        .map { |input| input[:name][/\[(\w+)\]/, 1] }
    end

    context "for the write tier" do
      before { sign_in(accountant) }

      it "is linked from the reading page" do
        returned_debit.update!(comment: "Rückruf vereinbart")
        get direct_debit_path(returned_debit)

        expect(html).to have_link(href: edit_direct_debit_path(returned_debit))
        expect(html).to have_text(I18n.t("fin.payments.debit_help.comment"))
        expect(html).to have_no_text(I18n.t("fin.payments.debit_help.try_skip"))
      end

      context "sent from another page with a return_url" do
        let(:origin) { "/fin/fees?f=x" }
        let(:changes) { {comment: "Rückruf vereinbart"} }

        it "leads back there from the reading page, keeps it on the edit page and returns there on save" do
          get direct_debit_path(returned_debit, return_url: origin)
          expect(html).to have_link("Zurück", href: origin)
          expect(html).to have_link(href: edit_direct_debit_path(returned_debit, return_url: origin))

          get edit_direct_debit_path(returned_debit, return_url: origin)
          expect(html).to have_css("form[action='#{direct_debit_path(returned_debit, return_url: origin)}']")
          expect(html).to have_link(href: direct_debit_path(returned_debit, return_url: origin))

          patch direct_debit_path(returned_debit, return_url: origin), params: params.merge(stay: "1")
          expect(response).to redirect_to(edit_direct_debit_path(returned_debit, return_url: origin))

          patch direct_debit_path(returned_debit, return_url: origin), params: params
          expect(response).to redirect_to(origin)
        end

        %w[https://example.com/x //example.com/x javascript:alert(1)].each do |url|
          it "ignores #{url}, which is no path of this application" do
            get direct_debit_path(returned_debit, return_url: url)
            expect(html).to have_link("Zurück zu Einzüge", href: direct_debits_path)

            patch direct_debit_path(returned_debit, return_url: url), params: params
            expect(response).to redirect_to(direct_debit_path(returned_debit))
          end
        end
      end

      context "of a debit in a SEPA file" do
        let(:changes) { {comment: "Rückruf vereinbart", amount_eur: "1,00", description: "anders"} }

        it "changes the comment only" do
          get edit_direct_debit_path(returned_debit)
          expect(inputs).to eq(%w[comment])

          patch direct_debit_path(returned_debit), params: params

          expect(response).to redirect_to(direct_debit_path(returned_debit))
          expect(returned_debit.reload).to have_attributes(comment: "Rückruf vereinbart", amount_cents: 20_000,
            description: "Beitrag")
        end
      end

      context "of a debit only announced" do
        let(:changes) do
          {amount_eur: "1.234,50", mandate_date: "09.10.2025", dbtr_iban: "DE02120300000000202051",
           try_skip: "1", comment: "neu"}
        end

        before { returned_debit.update!(payment_status: "pre_notified") }

        it "changes its payment data, with hitobito's date field and the money input" do
          get edit_direct_debit_path(returned_debit)
          expect(inputs).to contain_exactly("amount_eur", "description", "endtoend_id", "try_skip", "comment",
            "mandate_date", "dbtr_name", "dbtr_iban", "dbtr_bic", "dbtr_address")
          expect(html).to have_css("input.date[name$='[mandate_date]']")
          expect(html).to have_field("wsjrdp_direct_debit_pre_notification[amount_eur]", with: "200,00")
          expect(html).to have_text(I18n.t("fin.payments.debit_help.try_skip"))
          expect(html).to have_text(I18n.t("fin.payments.debit_help.comment"))

          patch direct_debit_path(returned_debit), params: params.merge(stay: "1")

          expect(response).to redirect_to(edit_direct_debit_path(returned_debit))
          expect(returned_debit.reload).to have_attributes(amount_cents: 123_450,
            mandate_date: Date.new(2025, 10, 9), try_skip: true, comment: "neu")
        end
      end
    end

    context "for the manage tier" do
      let(:manager) { Fabricate(Group::Root::FinanceManager.name.to_sym, group: groups(:root)).person }
      let(:changes) { {payment_status: "skipped", mandate_id: "wsjrdp-neu"} }

      # The manage tier is elevated: it holds once the session picks it
      # (Wsjrdp2027::FinanceCap), not by default.
      before do
        sign_in(manager)
        get fin_payments_path(max_finance_permission: "finance_manage")
      end

      it "also changes the status and the mandate reference of a debit only announced" do
        returned_debit.update!(payment_status: "pre_notified")

        get edit_direct_debit_path(returned_debit)
        expect(inputs).to include("payment_status", "mandate_id")
        expect(html).to have_select("wsjrdp_direct_debit_pre_notification[payment_status]",
          with_options: ["Einzug ausgesetzt (skipped)"])

        patch direct_debit_path(returned_debit), params: params
        expect(returned_debit.reload).to have_attributes(payment_status: "skipped", mandate_id: "wsjrdp-neu")
      end

      it "changes the status, but not the mandate reference, once the debit is in a SEPA file" do
        get edit_direct_debit_path(returned_debit)
        expect(inputs).to eq(%w[payment_status comment])

        patch direct_debit_path(returned_debit), params: params
        expect(returned_debit.reload.payment_status).to eq("skipped")
        expect(returned_debit.mandate_id).not_to eq("wsjrdp-neu")
      end

      it "takes no status the list does not know" do
        returned_debit.update!(payment_status: "pre_notified")

        patch direct_debit_path(returned_debit), params: {wsjrdp_direct_debit_pre_notification: {payment_status: "paid"}}
        expect(returned_debit.reload.payment_status).to eq("pre_notified")
      end
    end

    it "leaves the manage tier's fields to a session that picked it" do
      manager = Fabricate(Group::Root::FinanceManager.name.to_sym, group: groups(:root)).person
      sign_in(manager)
      returned_debit.update!(payment_status: "pre_notified")

      get edit_direct_debit_path(returned_debit)
      expect(inputs).not_to include("payment_status", "mandate_id")
    end

    context "for the write tier, below manage" do
      let(:changes) { {payment_status: "skipped", mandate_id: "wsjrdp-neu", comment: "ok"} }

      before do
        sign_in(accountant)
        returned_debit.update!(payment_status: "pre_notified")
      end

      it "leaves status and mandate reference alone" do
        get edit_direct_debit_path(returned_debit)
        expect(inputs).not_to include("payment_status", "mandate_id")

        patch direct_debit_path(returned_debit), params: params
        expect(returned_debit.reload).to have_attributes(payment_status: "pre_notified", comment: "ok")
        expect(returned_debit.mandate_id).not_to eq("wsjrdp-neu")
      end
    end

    context "for the audit tier" do
      let(:changes) { {comment: "nein"} }

      before { sign_in(auditor) }

      it "shows the debit without Bearbeiten and refuses to edit" do
        get direct_debit_path(returned_debit)
        expect(response).to have_http_status(:ok)
        expect(html).to have_no_link(href: edit_direct_debit_path(returned_debit))

        expect { get edit_direct_debit_path(returned_debit) }.to raise_error(CanCan::AccessDenied)
        expect { patch direct_debit_path(returned_debit), params: params }.to raise_error(CanCan::AccessDenied)
      end
    end
  end

  describe "a debit under its person (/fin/pn)" do
    let(:changes) { {comment: "Rückruf vereinbart"} }
    let(:params) { {wsjrdp_direct_debit_pre_notification: changes} }

    context "for the write tier" do
      before { sign_in(accountant) }

      it "shows the area's detail under the person's sheet, back to the person's Finanzen" do
        get wsjrdp_direct_debit_pre_notification_path(returned_debit)

        expect(html).to have_link(I18n.t("fin.payments.back_to", tab: I18n.t("people.tabs.finance")),
          href: person_accounting_path(person))
        expect(html).to have_link(I18n.t("fin.payments.debit_page_area"), href: direct_debit_path(returned_debit))
        expect(html).to have_link(href: payment_order_path(debit_order))
        expect(html).to have_link(href: edit_wsjrdp_direct_debit_pre_notification_path(returned_debit))
      end

      it "edits there and returns to the page under the person" do
        get edit_wsjrdp_direct_debit_pre_notification_path(returned_debit)
        expect(html).to have_css("form[action='#{wsjrdp_direct_debit_pre_notification_path(returned_debit)}']")

        patch wsjrdp_direct_debit_pre_notification_path(returned_debit), params: params

        expect(response).to redirect_to(wsjrdp_direct_debit_pre_notification_path(returned_debit))
        expect(returned_debit.reload.comment).to eq("Rückruf vereinbart")
      end

      it "returns to the person's fee page it was opened from, after a save too" do
        returned_debit.update!(payment_status: "pre_notified")
        WsjrdpPaymentPlan.find_or_create_by!(wsjrdp_role: person.wsjrdp_role, single_payment: false) do |plan|
          plan.raw_installments_eur = [2026, 100, 100]
        end
        fee_page = "/people/#{person.id}/fee"
        get fee_page
        link = html.all("a[href^='#{wsjrdp_direct_debit_pre_notification_path(returned_debit)}?']").first
        expect(link[:href]).to eq(wsjrdp_direct_debit_pre_notification_path(returned_debit, return_url: fee_page))

        get link[:href]
        expect(html).to have_link("Zurück", href: fee_page)
        get html.find_link(href: /#{Regexp.escape(edit_wsjrdp_direct_debit_pre_notification_path(returned_debit))}/)[:href]
        patch html.find("form[action^='#{wsjrdp_direct_debit_pre_notification_path(returned_debit)}']")[:action],
          params: params

        expect(response).to redirect_to(fee_page)
      end

      it "links the area's page to the one under the person" do
        get direct_debit_path(returned_debit)

        expect(html).to have_link(I18n.t("fin.payments.debit_page_person"),
          href: wsjrdp_direct_debit_pre_notification_path(returned_debit))
      end

      it "sends a debit without a person to the area's pages" do
        returned_debit.update_columns(subject_type: nil, subject_id: nil)

        get wsjrdp_direct_debit_pre_notification_path(returned_debit)
        expect(response).to redirect_to(direct_debit_path(returned_debit))
        get edit_wsjrdp_direct_debit_pre_notification_path(returned_debit)
        expect(response).to redirect_to(edit_direct_debit_path(returned_debit))

        get direct_debit_path(returned_debit)
        expect(html).to have_no_link(I18n.t("fin.payments.debit_page_person"))
      end
    end

    it "lets the audit tier read, but not edit" do
      auditor = Fabricate(Group::Extern::FinanceAuditor.name.to_sym,
        group: Group::Extern.create!(name: "Extern", parent: groups(:root))).person
      sign_in(auditor)

      get wsjrdp_direct_debit_pre_notification_path(returned_debit)

      expect(response).to have_http_status(:ok)
      expect(html).to have_no_link(href: edit_wsjrdp_direct_debit_pre_notification_path(returned_debit))
      expect { patch wsjrdp_direct_debit_pre_notification_path(returned_debit), params: params }
        .to raise_error(CanCan::AccessDenied)
    end

    context "for a unit's leader without finance rights, who may :log the unit's people" do
      before { sign_in(Fabricate(Group::Unit::Manager.name.to_sym, group: groups(:unit_a)).person) }

      it "is closed for reading" do
        expect { get wsjrdp_direct_debit_pre_notification_path(returned_debit) }.to raise_error(CanCan::AccessDenied)
      end

      it "is closed for saving" do
        expect { patch wsjrdp_direct_debit_pre_notification_path(returned_debit), params: params }
          .to raise_error(CanCan::AccessDenied)
        expect(returned_debit.reload.comment).not_to eq("Rückruf vereinbart")
      end
    end
  end

  context "links from other pages" do
    before { sign_in(accountant) }

    it "leads from a pre-notification, an entry, the Beiträge overview and an account to the orders" do
      get wsjrdp_direct_debit_pre_notification_path(returned_debit)
      expect(html).to have_link(href: payment_order_path(debit_order))
        .and have_link(href: direct_debit_path(returned_debit))

      get accounting_entry_path(return_entry)
      expect(html).to have_link(I18n.t("fin.payments.order_label", id: debit_order.id),
        href: payment_order_path(debit_order))

      get fees_path
      expect(html).to have_link(I18n.t("fin.payments.direct_debit_orders"))

      get wsjrdp_fin_account_path(account)
      get html.find_link(I18n.t("fin.payments.account_orders"))[:href]
      expect(rows("pocol")).to eq([debit_order.id.to_s])
    end
  end

  context "for the read tier" do
    before { sign_in(reader) }

    it "shows an order's status in words only" do
      get payment_order_path(debit_order)

      expect(html).to have_css(".fin-detail-list dd", text: "XML erzeugt")
      expect(html).to have_no_text("xml_generated")
    end

    it "shows the orders, but neither the debits nor the returns" do
      get fin_payments_path
      expect(html).to have_no_css("ul.nav-sub li", text: I18n.t("fin.tabs.direct_debits"))
      expect(html).to have_no_css("#main a", text: I18n.t("fin.payments.tiles.debits"))

      get payment_order_path(debit_order)
      expect(response).to have_http_status(:ok)
      expect(html).to have_no_css("td.ddcol-person")

      expect { get direct_debits_path }.to raise_error(CanCan::AccessDenied)
      expect { get payment_returns_path }.to raise_error(CanCan::AccessDenied)
    end
  end
end
