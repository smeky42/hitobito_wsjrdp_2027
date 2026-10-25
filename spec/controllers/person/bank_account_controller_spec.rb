# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe Person::BankAccountController, type: :controller do
  render_views

  let(:yp) { people(:yp_a_1) }
  let(:finance) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }
  let(:auditor) do
    Fabricate(Group::Extern::FinanceAuditor.name.to_sym,
      group: Group::Extern.create!(name: "Extern", parent: groups(:root))).person
  end
  let(:order) do
    WsjrdpPaymentInitiation.create!(status: "planned", sepa_schema: "pain.008.001.08",
      message_identification: "MSG-1", number_of_transactions: 2, control_sum_cents: 70_000)
  end
  let!(:announced) { debit("pre_notified", Date.new(2026, 11, 5)) }
  let!(:collected) { debit("xml_generated", Date.new(2026, 8, 5)) }

  let(:account) do
    {sepa_name: "Erika Mustermann", sepa_address: "Musterstraße 1, 12345 Musterstadt",
     sepa_mail: "erika@example.org", sepa_iban: "DE89 3704 0044 0532 0130 00", sepa_bic: "COBADEFFXXX",
     sepa_mandate_id: "wsjrdp2027#{yp.id}"}
  end

  def debit(status, date)
    WsjrdpDirectDebitPreNotification.create!(payment_initiation: order, subject: yp, author: yp,
      payment_status: status, amount_cents: 40_000, collection_date: date, debit_sequence_type: "RCUR",
      description: "WSJ 2027 Rate", dbtr_name: "Alt", dbtr_iban: "DE02120300000000202051",
      endtoend_id: "E2E-#{status}")
  end

  def update(extra = {})
    put :update, params: {person_id: yp.id, person: account, format: :turbo_stream}.merge(extra)
  end

  context "for the finance tier" do
    before { sign_in(finance) }

    it "offers the announced debit, checked, in the form" do
      get :edit, params: {person_id: yp.id, format: :turbo_stream}

      html = Capybara.string(Nokogiri::HTML(response.body).at("template").inner_html)
      expect(html).to have_field("person[sepa_iban]").and have_field("person[sepa_mandate_id]")
      expect(html).to have_checked_field("debit_ids_#{announced.id}")
      expect(html).to have_no_field("debit_ids_#{collected.id}")
    end

    it "brings its scripts along, on a page of its own too" do
      get :edit, params: {person_id: yp.id}

      expect(response.body).to include("wsjrdpBankAccountFormBound").and include("wsjrdpCopyFromParticipantBound")
    end

    it "offers the participant's address and mail, named in the tooltip, where there is one" do
      yp.update_columns(street: "Musterstraße", housenumber: "1", zip_code: "12345", town: "Musterstadt",
        email: "erika@example.org")
      get :edit, params: {person_id: yp.id, format: :turbo_stream}

      html = Capybara.string(Nokogiri::HTML(response.body).at("template").inner_html)
      expect(html).to have_css("button[data-copy-from-participant='address']" \
        "[data-copy-value='Musterstraße 1, 12345 Musterstadt'][title*='Musterstraße 1']")
      expect(html).to have_css("button[data-copy-from-participant='email'][data-copy-value='erika@example.org']")

      yp.update_columns(street: nil, housenumber: nil, zip_code: nil, town: nil)
      get :edit, params: {person_id: yp.id, format: :turbo_stream}

      html = Capybara.string(Nokogiri::HTML(response.body).at("template").inner_html)
      expect(html).to have_css(".wsjrdp-field-aside button[hidden][data-copy-from-participant='address']",
        visible: :all)
    end

    it "proposes today as the mandate date and offers the previous one" do
      yp.update_columns(print_at: Date.new(2025, 9, 1))
      get :edit, params: {person_id: yp.id, format: :turbo_stream}

      html = Capybara.string(Nokogiri::HTML(response.body).at("template").inner_html)
      expect(html).to have_field("person[sepa_mandate_date]", with: I18n.l(Time.zone.today))
      expect(html).to have_css("button[data-sepa-mandate-date-set='01.09.2025']")
      expect(html).to have_text("Bisher: 01.09.2025")
      expect(html).to have_css("[data-sepa-mandate-date-past][hidden]", visible: :all)
    end

    it "offers no previous mandate date for a person never printed" do
      yp.update_columns(print_at: nil)
      get :edit, params: {person_id: yp.id, format: :turbo_stream}

      html = Capybara.string(Nokogiri::HTML(response.body).at("template").inner_html)
      expect(html).to have_no_css("button[data-sepa-mandate-date-set]")
      expect(html).to have_no_text("Bisher:")
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

    it "takes another mandate reference of the person, but none of another person" do
      update(person: account.merge(sepa_mandate_id: "WSJRDP2027-#{yp.id}-b"))
      expect(yp.reload.sepa_mandate_id).to eq("wsjrdp2027-#{yp.id}-b")

      update(person: account.merge(sepa_mandate_id: "wsjrdp2027#{yp.id}1", sepa_name: "Andere"))
      expect(response).to have_http_status(422)
      expect(yp.reload.sepa_name).to eq("Erika Mustermann")
    end

    it "refuses a mandate date that is no date, keeps everything and shows what was typed" do
      update(person: account.merge(sepa_mandate_date: "31.02.2026", sepa_name: "Andere"), debit_ids: [announced.id])

      expect(response).to have_http_status(422)
      expect(response.body).to include(I18n.t("people.sepa_account.mandate_date_invalid")).and include("31.02.2026")
      expect(yp.reload.sepa_name).not_to eq("Andere")
      expect(announced.reload.dbtr_name).to eq("Alt")
    end

    it "takes a blank mandate date as the print of the registration" do
      yp.update_columns(print_at: Date.new(2025, 9, 1))

      update(person: account.merge(sepa_mandate_date: ""))

      expect(yp.reload.sepa_mandate_date).to eq(Date.new(2025, 9, 1))
    end

    it "refuses an invalid IBAN and keeps everything" do
      update(person: account.merge(sepa_iban: "DE00 1234"), debit_ids: [announced.id])

      expect(response).to have_http_status(422)
      expect(response.body).to include(I18n.t("people.finance_fields.invalid_iban"))
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

    it "shows the current account, signed today without a mandate date, in the browser" do
      yp.update_columns(print_at: nil)
      get :mandate, params: {person_id: yp.id}

      expect(response.media_type).to eq("application/pdf")
      expect(response.headers["Content-Disposition"]).to start_with("inline")
      expect(pdf_text).to include("DE89370400440532013000").and include("Erika Mustermann")
        .and include(Time.zone.today.strftime("%d.%m.%Y"))
    end

    it "is signed on the mandate date" do
      yp.update!(sepa_mandate_date: Date.new(2026, 10, 20))
      get :mandate, params: {person_id: yp.id}

      expect(pdf_text).to include("20.10.2026")
    end

    it "refuses a person the mandate cannot be made for" do
      yp.update_columns(sepa_iban: nil, town: nil)

      get :mandate, params: {person_id: yp.id}

      expect(response).to have_http_status(422)
    end

    it "takes the signing date from outside and downloads" do
      get :mandate, params: {person_id: yp.id, signed_on: "01.12.2026", download: "1"}

      expect(response.headers["Content-Disposition"]).to start_with("attachment")
      expect(pdf_text).to include("01.12.2026")
    end
  end

  it "keeps the mandate date, with the print of the registration as default" do
    sign_in(finance)
    yp.update_columns(print_at: Date.new(2025, 9, 1))
    expect(yp.reload.sepa_mandate_date).to eq(Date.new(2025, 9, 1))

    update(person: account.merge(sepa_mandate_date: "20.10.2026"), debit_ids: [announced.id])

    expect(yp.reload.sepa_mandate_date).to eq(Date.new(2026, 10, 20))
    expect(announced.reload.mandate_date).to eq(Date.new(2026, 10, 20))
  end

  it "is closed to the audit tier" do
    sign_in(auditor)

    expect { get :edit, params: {person_id: yp.id, format: :turbo_stream} }.to raise_error(CanCan::AccessDenied)
    expect { update }.to raise_error(CanCan::AccessDenied)
    expect { get :mandate, params: {person_id: yp.id} }.to raise_error(CanCan::AccessDenied)
  end
end
