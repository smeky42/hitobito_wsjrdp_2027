# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe Person::FeeController do
  render_views

  # A migrated database holds a payment plan per role, a schema-loaded one none.
  def ensure_payment_plan(person)
    WsjrdpPaymentPlan.find_or_create_by!(wsjrdp_role: person.wsjrdp_role, single_payment: false) do |plan|
      plan.raw_installments_eur = [2026, 100, 100]
    end
  end

  # Only the person themselves may edit a person who is in no layer.
  it "renders a person without any role in the root group" do
    person = Fabricate(:person)
    expect(person.primary_group).to be_nil
    ensure_payment_plan(person)
    sign_in(person)

    get :show, params: {person_id: person.id}
    expect(response).to be_successful
    expect(assigns(:group)).to eq(Group.root)
  end

  it "uses the group of the URL, without one the primary group" do
    yp = people(:yp_a_1)
    ensure_payment_plan(yp)
    sign_in(people(:admin))

    get :show, params: {group_id: groups(:ist_a).id, id: yp.id}
    expect(assigns(:group)).to eq(groups(:ist_a))

    get :show, params: {person_id: yp.id}
    expect(assigns(:group)).to eq(yp.primary_group)
  end

  describe "the bank account" do
    let(:yp) { people(:yp_a_1) }
    let(:auditor) do
      Fabricate(Group::Extern::FinanceAuditor.name.to_sym,
        group: Group::Extern.create!(name: "Extern", parent: groups(:root))).person
    end

    before do
      ensure_payment_plan(yp)
      yp.update_columns(sepa_name: "Erika Mustermann", sepa_iban: "DE02120300000000202051",
        sepa_bic: "BYLADEM1001", status: "printed")
    end

    [:yp, :auditor].each do |viewer|
      it "shows the account holder, IBAN, BIC and mandate to #{viewer}" do
        sign_in(send(viewer))

        get :show, params: {person_id: yp.id}

        section = Capybara.string(response.body).find("section.bank-account")
        expect(section).to have_text("Erika Mustermann")
          .and have_text("BYLADEM1001")
          .and have_text(yp.sepa_mandate_id)
        expect(section.text.delete(" ")).to include("DE02120300000000202051")
        expect(section).to have_css("a.sepa-account-change[href^='mailto:finanzen@worldscoutjamboree.de?']")
      end
    end

    context "for the finance tier" do
      before { sign_in(Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person) }

      it "offers the SEPA mandate once it can be made" do
        yp.update_columns(birthday: Date.new(2010, 5, 1), town: "Musterstadt", sepa_address: "Musterstraße 1",
          sepa_mandate_date: Date.new(2025, 9, 1))

        get :show, params: {person_id: yp.id}

        section = Capybara.string(response.body).find("section.bank-account")
        expect(section).to have_link(href: mandate_person_bank_account_path(yp))
        expect(section).to have_no_css(".sepa-mandate-missing")
      end

      it "disables the SEPA mandate and names what is missing" do
        yp.update_columns(birthday: nil, town: nil, sepa_mandate_date: nil)

        get :show, params: {person_id: yp.id}

        section = Capybara.string(response.body).find("section.bank-account")
        expect(section).to have_no_link(href: mandate_person_bank_account_path(yp))
        expect(section).to have_css("a.disabled", text: I18n.t("people.sepa_account.mandate_view"))
        expect(section.find(".sepa-mandate-missing")).to have_text(Person.human_attribute_name(:birthday))
          .and have_text(Person.human_attribute_name(:town))
          .and have_text(Person.human_attribute_name(:sepa_mandate_date))
      end
    end
  end

  describe "the statement" do
    let(:yp) { people(:yp_a_1) }

    before { ensure_payment_plan(yp) }

    it "renders the pdf for an administrator" do
      sign_in(people(:admin))

      get :statement, params: {person_id: yp.id}

      expect(response).to be_successful
      expect(response.media_type).to eq("application/pdf")
      expect(response.body).to start_with("%PDF")
      expect(response.headers["Content-Disposition"]).to start_with("inline")
      expect(response.headers["Content-Disposition"]).to include("Beitragszahlungen")
    end

    it "renders the pdf for the person themselves" do
      sign_in(yp)

      get :statement, params: {person_id: yp.id}

      expect(response).to be_successful
      expect(response.body).to start_with("%PDF")
    end

    it "refuses it to a leader of another unit" do
      sign_in(people(:ul_b_1))

      expect { get :statement, params: {person_id: yp.id} }.to raise_error(CanCan::AccessDenied)
    end
  end

  it "offers the finance write tier the Rücklastschriften button" do
    person = people(:yp_a_1)
    ensure_payment_plan(person)
    sign_in(Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person)

    get :show, params: {person_id: person.id}
    expect(response).to be_successful
    expect(response.body).to include(edit_person_debit_return_path(person))
  end

  describe "the Ratenplan section" do
    let(:yp) { people(:yp_a_1) }
    let(:finance) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }

    before do
      ensure_payment_plan(yp)
      Wsj27RdpFeeRule.create!(people_id: yp.id, status: "deleted", activated_at: 3.days.ago, deleted_at: 1.day.ago,
        custom_installments_starting_year: 2026, custom_installments_cents: [0, 5_000],
        custom_installments_issue: "HELP-10", deleted_by: finance)
      active = Wsj27RdpFeeRule.create!(people_id: yp.id, status: "active", activated_at: 1.day.ago,
        custom_installments_starting_year: 2026, custom_installments_cents: [0, 10_000],
        custom_installments_issue: "HELP-11", custom_installments_comment: "Vereinbarung aktiv",
        custom_installments_payment_method: "credit_transfer", activated_by: finance)
      Wsj27RdpFeeRule.create!(people_id: yp.id, status: "planned",
        custom_installments_starting_year: 2026, custom_installments_cents: [0, 0, 7_000],
        custom_installments_issue: "HELP-12", custom_installments_comment: "Vereinbarung geplant")
      yp.update!(Wsjrdp2027::ParticipationFee.person_installments_attrs(active))
    end

    def page_as(viewer)
      sign_in(viewer)
      get :show, params: {person_id: yp.id}
      expect(response).to be_successful
      response.body
    end

    def section(body) = Nokogiri::HTML(body).at_css("section.installments")

    it "shows the person themselves the section without issues, plans, history or buttons" do
      html = section(page_as(yp))

      expect(html).to be_present
      expect(html.text).not_to include("HELP-11")
      expect(html.text).not_to include("HELP-12")
      expect(html.text).not_to include("HELP-10")
      expect(html.text).not_to include("Vereinbarung")
      expect(html.to_html).not_to include(edit_person_installments_path(yp))
    end

    it "shows a CMT leader the issue, the planned plan and the history, without comments or buttons" do
      html = section(page_as(Fabricate(Group::Root::Leader.name.to_sym, group: groups(:root)).person))

      expect(html.text).to include("HELP-11").and include("HELP-12").and include("HELP-10")
      expect(html.text).not_to include("Vereinbarung")
      expect(html.to_html).not_to include(edit_person_installments_path(yp))
    end

    it "carries the anchors the status page links to" do
      doc = Nokogiri::HTML(page_as(finance))

      expect(doc.at_css("section#payment_plan_#{yp.id}.installments")).to be_present
      expect(doc.at_css("section#total_fee_#{yp.id}.fee-reduction")).to be_present
    end

    it "shows finance the comments and the buttons" do
      html = section(page_as(finance))

      expect(html.text).to include("Vereinbarung aktiv").and include("Vereinbarung geplant")
      expect(html.to_html).to include(activate_person_installments_path(yp, context: "person"))
      expect(html.to_html).to include(ERB::Util.html_escape(edit_person_installments_path(yp, mode: "edit", context: "person")))
    end
  end

  describe "the Beitragshöhe section" do
    let(:yp) { people(:yp_a_1) }

    before do
      ensure_payment_plan(yp)
      yp.update!(wsjrdp_total_fee_reduction: 250, wsjrdp_total_fee_reduction_hint: "Härtefall",
        wsjrdp_total_fee_reduction_issue: "HELP-123", wsjrdp_total_fee_reduction_comment: "Nachweis liegt vor",
        planned_total_fee_reduction: "400", planned_total_fee_reduction_comment: "Erhöhung")
    end

    def page_as(viewer)
      sign_in(viewer)
      get :show, params: {person_id: yp.id}
      expect(response).to be_successful
      response.body
    end

    def section(body) = Nokogiri::HTML(body).at_css("section.fee-reduction")

    it "is not shown to the person themselves or their unit leader" do
      expect(section(page_as(yp))).to be_nil
      expect(section(page_as(people(:ul_a_1)))).to be_nil
    end

    it "shows the reduction and the plan to a CMT leader, without comments or buttons" do
      html = section(page_as(Fabricate(Group::Root::Leader.name.to_sym, group: groups(:root)).person))

      expect(html.text).to include("Härtefall").and include("HELP-123").and include("Geplant: Reduktion 400")
      expect(html.text).not_to include("Nachweis liegt vor")
      expect(html.text).not_to include("Erhöhung")
      expect(html.to_html).not_to include(activate_person_fee_reduction_path(yp))
      expect(html.to_html).not_to include(edit_person_fee_reduction_path(yp))
    end

    it "shows comments and the plan's buttons to finance, and comes after the installments" do
      body = page_as(Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person)
      html = section(body)

      expect(html.text).to include("Nachweis liegt vor").and include("Erhöhung")
      expect(html.to_html).to include(activate_person_fee_reduction_path(yp))
        .and include(discard_person_fee_reduction_path(yp))
      expect(body.index("Ratenplan")).to be < body.index("Beitragshöhe")
    end

    it "lists the changes of the active reduction only, never the comment" do
      yp.update!(planned_total_fee_reduction: nil)
      with_versioning do
        yp.update!(wsjrdp_total_fee_reduction: 300, wsjrdp_total_fee_reduction_comment: "Neu vereinbart")
        yp.update!(wsjrdp_total_fee_reduction_comment: "Nur der Kommentar")
        yp.update!(nickname: "Anderswo")
      end

      html = section(page_as(Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person))
      expect(html.text).to include("250€ → 300€")
      expect(html.text).not_to include("Neu vereinbart")
      expect(html.text).not_to include("Anderswo")
    end

    it "morphs page refreshes and keeps the scroll position" do
      body = page_as(Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person)

      expect(body).to include('<meta name="turbo-refresh-method" content="morph">')
        .and include('<meta name="turbo-refresh-scroll" content="preserve">')
    end
  end
end
