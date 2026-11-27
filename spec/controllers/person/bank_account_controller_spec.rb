# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe Person::BankAccountController, type: :controller do
  before_all(setup_fixtures: true) {}

  let(:yp) { people(:yp_a_1) }
  let_it_be(:finance) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }
  let_it_be(:order) do
    WsjrdpPaymentInitiation.create!(status: "planned", sepa_schema: "pain.008.001.08",
      message_identification: "MSG-1", number_of_transactions: 2, control_sum_cents: 70_000)
  end
  let_it_be(:announced, refind: true) { debit("pre_notified", Date.new(2026, 11, 5)) }
  let_it_be(:collected, refind: true) { debit("xml_generated", Date.new(2026, 8, 5)) }

  let(:account) do
    {sepa_name: "Erika Mustermann", sepa_address: "Musterstraße 1, 12345 Musterstadt",
     sepa_mail: "erika@example.org", sepa_iban: "DE89 3704 0044 0532 0130 00", sepa_bic: "COBADEFFXXX",
     sepa_mandate_id: "wsjrdp2027#{yp.id}"}
  end

  def debit(status, date)
    person = people(:yp_a_1)
    WsjrdpDirectDebitPreNotification.create!(payment_initiation: order, subject: person, author: person,
      payment_status: status, amount_cents: 40_000, collection_date: date, debit_sequence_type: "RCUR",
      description: "WSJ 2027 Rate", dbtr_name: "Alt", dbtr_iban: "DE02120300000000202051",
      endtoend_id: "E2E-#{status}")
  end

  def update(extra = {})
    put :update, params: {person_id: yp.id, person: account, format: :turbo_stream}.merge(extra)
  end

  def template_html = Capybara.string(Nokogiri::HTML(response.body).at("template").inner_html)

  def edit_form
    get :edit, params: {person_id: yp.id, format: :turbo_stream}
    template_html
  end

  def person_errors = assigns(:person).errors

  context "for the finance tier, in the form" do
    render_views

    before { sign_in(finance) }

    it "offers the announced debit and the participant's data, hiding the hints for an unchanged account" do
      yp.update_columns(street: "Musterstraße", housenumber: "1", zip_code: "12345", town: "Musterstadt",
        email: "erika@example.org", sepa_mandate_date: Date.new(2025, 9, 1), sepa_iban: "DE02120300000000202051")
      html = edit_form

      aggregate_failures do
        expect(html).to have_checked_field("debit_ids_#{announced.id}")
        expect(html).to have_no_field("debit_ids_#{collected.id}")
        expect(html).to have_css("button[data-copy-from-participant='address']" \
          "[data-copy-value='Musterstraße 1, 12345 Musterstadt'][title*='Musterstraße 1']")
        expect(html).to have_css("button[data-copy-from-participant='email'][data-copy-value='erika@example.org']")
        expect(html).to have_field("person[sepa_mandate_date]", with: I18n.l(Time.zone.today))
        expect(html).to have_css("button[data-sepa-mandate-date-set='01.09.2025']")
        expect(html).to have_css("[data-sepa-mandate-date-past][hidden]", visible: :all)
        expect(html).to have_css("[data-sepa-mandate-id-hint][hidden]", visible: :all)
        expect(html).to have_css("input[data-sepa-iban='DE02120300000000202051']")
      end
    end

    it "hides the participant's address and offers no mandate date without stored ones" do
      yp.update_columns(street: nil, housenumber: nil, zip_code: nil, town: nil,
        print_at: Date.new(2025, 9, 1), sepa_mandate_date: nil)
      html = edit_form

      aggregate_failures do
        expect(html).to have_css("button[hidden][data-copy-from-participant='address']", visible: :all)
        expect(html).to have_field("person[sepa_mandate_date]", with: "", disabled: true)
        expect(html).to have_no_css("button[data-sepa-mandate-date-set]")
      end
    end

    it "brings its scripts along, on a page of its own too" do
      get :edit, params: {person_id: yp.id}

      expect(response.body).to include("wsjrdpBankAccountFormBound").and include("wsjrdpCopyFromParticipantBound")
    end

    it "refuses a mandate date that is no date, keeps everything and shows what was typed with the new-IBAN hint" do
      yp.update_columns(sepa_mandate_date: Date.new(2025, 9, 1), sepa_iban: "DE02120300000000202051")
      update(person: account.merge(sepa_mandate_date: "31.02.2026", sepa_name: "Andere"), debit_ids: [announced.id])

      aggregate_failures do
        expect(response).to have_http_status(422)
        expect(template_html).to have_field("person[sepa_mandate_date]", with: "31.02.2026")
        expect(template_html).to have_css("[data-sepa-mandate-id-hint]:not([hidden])")
        expect(yp.reload.sepa_name).not_to eq("Andere")
        expect(announced.reload.dbtr_name).to eq("Alt")
      end
    end
  end

  context "for the finance tier, saving" do
    before { sign_in(finance) }

    it "refuses a mandate date sent without a stored one" do
      update(person: account.merge(sepa_mandate_date: "20.10.2026", sepa_name: "Andere"))

      expect(response).to have_http_status(422)
      expect(person_errors.added?(:sepa_mandate_date, I18n.t("people.sepa_account.mandate_date_before_print")))
        .to be(true)
      expect(yp.reload.sepa_name).not_to eq("Andere")
      expect(yp.sepa_mandate_date).to be_nil
    end

    it "saves the account, the announced debit and the comment as a note" do
      update(debit_ids: [announced.id], comment: "HELP-1 neue Bank")

      expect(yp.reload).to have_attributes(sepa_name: "Erika Mustermann", sepa_iban: "DE89370400440532013000",
        sepa_bic: "COBADEFFXXX")
      expect(announced.reload).to have_attributes(dbtr_name: "Erika Mustermann",
        dbtr_iban: "DE89370400440532013000", dbtr_bic: "COBADEFFXXX")
      expect(collected.reload.dbtr_iban).to eq("DE02120300000000202051")
      expect(Note.where(subject: yp).last.text).to include("HELP-1 neue Bank")
    end

    it "leaves an unchecked debit and writes no note without a comment" do
      expect { update }.not_to change { Note.count }

      expect(announced.reload.dbtr_iban).to eq("DE02120300000000202051")
    end

    it "takes another mandate reference of the person" do
      update(person: account.merge(sepa_mandate_id: "WSJRDP2027-#{yp.id}-b"))

      expect(yp.reload.sepa_mandate_id).to eq("wsjrdp2027-#{yp.id}-b")
    end

    it "refuses a mandate reference of another person" do
      update(person: account.merge(sepa_mandate_id: "wsjrdp2027#{yp.id}1"))

      expect(response).to have_http_status(422)
      expect(yp.reload.sepa_mandate_id).not_to eq("wsjrdp2027#{yp.id}1")
    end

    it "clears the mandate date with an empty field, without the print as fallback" do
      yp.update_columns(status: "printed", print_at: Date.new(2025, 9, 1), sepa_mandate_date: Date.new(2026, 10, 20))
      announced.update_columns(try_skip: true)

      update(person: account.merge(sepa_mandate_date: ""))

      expect(yp.reload.sepa_mandate_date).to be_nil
    end

    it "changes the stored mandate date, in the announced debit too" do
      yp.update_columns(sepa_mandate_date: Date.new(2025, 9, 1))

      update(person: account.merge(sepa_mandate_date: "20.10.2026"), debit_ids: [announced.id])

      expect(yp.reload.sepa_mandate_date).to eq(Date.new(2026, 10, 20))
      expect(announced.reload.mandate_date).to eq(Date.new(2026, 10, 20))
    end

    it "carries a new mandate reference into the announced debit, without the manage tier" do
      update(person: account.merge(sepa_mandate_id: "wsjrdp2027#{yp.id}b"), debit_ids: [announced.id])

      expect(announced.reload.mandate_id).to eq("wsjrdp2027#{yp.id}b")
    end

    it "saves a new IBAN under the stored mandate reference all the same" do
      yp.update!(sepa_iban: "DE02120300000000202051")

      update

      expect(response).to have_http_status(:ok)
      expect(yp.reload.sepa_iban).to eq("DE89370400440532013000")
    end

    it "refuses an invalid IBAN and keeps everything" do
      update(person: account.merge(sepa_iban: "DE00 1234"), debit_ids: [announced.id])

      expect(response).to have_http_status(422)
      expect(person_errors).to include(:sepa_iban)
      expect(announced.reload.dbtr_name).to eq("Alt")
    end
  end

  describe "the updated SEPA mandate" do
    def pdf_text = PDF::Inspector::Text.analyze(response.body).strings.join(" ")

    before do
      yp.update_columns(sepa_name: "Erika Mustermann", sepa_iban: "DE89370400440532013000", sepa_address: "Musterstraße 1",
        town: "Musterstadt", birthday: Date.new(2010, 5, 1))
      WsjrdpPaymentPlan.find_or_create_by!(wsjrdp_role: yp.wsjrdp_role, single_payment: false) do |plan|
        plan.raw_installments_eur = [2026, 100, 100]
      end
      sign_in(finance)
    end

    it "signs it on the mandate date, in the browser" do
      yp.update_columns(sepa_mandate_date: Date.new(2026, 10, 20))
      expect(Wsjrdp2027::Export::Pdf::Registration).to receive(:render_sepa_mandate)
        .with(yp, signed_on: Date.new(2026, 10, 20)).and_return("%PDF-1.4\n")

      get :mandate, params: {person_id: yp.id}

      expect(response.media_type).to eq("application/pdf")
      expect(response.headers["Content-Disposition"]).to start_with("inline")
    end

    it "refuses a person without a mandate date" do
      yp.update_columns(print_at: Date.new(2025, 9, 1), sepa_mandate_date: nil)

      get :mandate, params: {person_id: yp.id}

      expect(response).to have_http_status(422)
    end

    it "refuses a person the mandate cannot be made for" do
      yp.update_columns(sepa_iban: nil, town: nil)

      get :mandate, params: {person_id: yp.id}

      expect(response).to have_http_status(422)
    end

    it "shows the current account, signed on a date from outside, as a download" do
      yp.update_columns(sepa_mandate_date: Date.new(2026, 10, 20))

      get :mandate, params: {person_id: yp.id, signed_on: "01.12.2026", download: "1"}

      expect(response.headers["Content-Disposition"]).to start_with("attachment")
      expect(pdf_text).to include("DE89370400440532013000", "Erika Mustermann", "01.12.2026")
    end
  end

  context "for an admin whose session works at the read tier" do
    let_it_be(:admin) { Fabricate(Group::Root::Admin.name.to_sym, group: groups(:root)).person }

    before do
      sign_in(admin)
      session[:max_finance_permission] = "finance_read"
    end

    it "names the announced debits it may not change, without offering them" do
      get :edit, params: {person_id: yp.id, format: :turbo_stream}

      expect(controller.view_context.editable_debits).to be_empty
      expect(controller.view_context.locked_debits).to eq([announced])
    end

    it "saves the account, but not in the announced debit" do
      update

      expect(yp.reload.sepa_iban).to eq("DE89370400440532013000")
      expect(announced.reload.dbtr_iban).to eq("DE02120300000000202051")
    end

    it "refuses an announced debit sent along" do
      expect { update(debit_ids: [announced.id]) }.to raise_error(CanCan::AccessDenied)
      expect(announced.reload.dbtr_iban).to eq("DE02120300000000202051")
    end
  end

  context "for the audit tier" do
    let_it_be(:auditor) do
      Fabricate(Group::Extern::FinanceAuditor.name.to_sym,
        group: Group::Extern.create!(name: "Extern", parent: groups(:root))).person
    end

    before { sign_in(auditor) }

    it "closes the form" do
      expect { get :edit, params: {person_id: yp.id, format: :turbo_stream} }.to raise_error(CanCan::AccessDenied)
    end

    it "refuses a save" do
      expect { update }.to raise_error(CanCan::AccessDenied)
    end

    it "refuses the mandate" do
      expect { get :mandate, params: {person_id: yp.id} }.to raise_error(CanCan::AccessDenied)
    end
  end
end
