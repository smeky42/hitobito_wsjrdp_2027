# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The person fee page (/people/:id/fee). Its sheet hangs below the group sheet,
# whose left navigation needs a group: PersonInPrimaryGroup supplies the
# person's primary group, or the root group for a person without one -- the
# root user has no role at all, and its page used to fail in that navigation.
describe Person::FeeController do
  render_views

  # The installments block reads the person's payment plan (by wsjrdp_role and
  # payment mode). A database built by the migrations already holds one per
  # role (20260419000100 seeds them, as CI does); a schema-loaded test
  # database holds none -- so take the existing plan or create one.
  def ensure_payment_plan(person)
    WsjrdpPaymentPlan.find_or_create_by!(wsjrdp_role: person.wsjrdp_role, single_payment: false) do |plan|
      plan.raw_installments_eur = [2026, 100, 100]
    end
  end

  # Nobody but the person themselves may edit a person who is in no layer, so
  # the page is opened by its owner -- as the root user opens their own.
  it "renders a person without any role in the root group" do
    person = Fabricate(:person)
    expect(person.primary_group).to be_nil
    ensure_payment_plan(person)
    sign_in(person)

    get :show, params: {person_id: person.id}
    expect(response).to be_successful
    expect(assigns(:group)).to eq(Group.root)
  end

  # The entries of the page as a PDF. It sits behind the page's own
  # authorization, so everybody who may read the page may print it -- the
  # person themselves included.
  describe "the statement" do
    let(:yp) { people(:yp_a_1) }

    before { ensure_payment_plan(yp) }

    it "offers it on the page, between the entries and the installments" do
      sign_in(people(:admin))

      get :show, params: {person_id: yp.id}

      expect(response.body).to include(statement_person_fee_path(yp))
      expect(response.body.index(statement_person_fee_path(yp)))
        .to be < response.body.index("Ratenplan")
    end

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

  # The deregistration form moved to its own "Abmeldung" sub-tab; the sibling
  # frame button for the debit returns stayed behind. The button row needs the
  # finance write tier (:update_finance and :create on AccountingEntry), which
  # the plain CMT leader of the fixtures does not hold.
  it "offers the Rücklastschriften button but no deregistration button" do
    person = people(:yp_a_1)
    ensure_payment_plan(person)
    sign_in(Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person)

    get :show, params: {person_id: person.id}
    expect(response).to be_successful
    expect(response.body).to include("Rücklastschriften")
    expect(response.body).not_to include("Abmeldung vorbereiten")
  end

  # "Beitragshöhe" at the end of the page: seen with :log on the person, the
  # comments with :log on accounting entries (audit tier), the buttons with
  # :update_finance. The person themselves and the unit leader see the page but
  # not the section.
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

    it "shows the person themselves the installments and how they are paid, nothing else" do
      html = section(page_as(yp))

      expect(html.text).to include("Soll Kontostand").and include("Zahlungsart: Überweisung")
      expect(html.text).not_to include("HELP-11")
      expect(html.text).not_to include("Vereinbarung")
      expect(html.text).not_to include("Geplant")
      expect(html.text).not_to include("Änderungen am Ratenplan")
      expect(html.to_html).not_to include(edit_person_installments_path(yp))
    end

    it "shows a CMT leader the issue, the planned plan and the history, without comments or buttons" do
      html = section(page_as(Fabricate(Group::Root::Leader.name.to_sym, group: groups(:root)).person))

      expect(html.text).to include("HELP-11").and include("Geplant: 2026-03: 70€").and include("HELP-12")
      expect(html.text).to include("Änderungen am Ratenplan").and include("HELP-10")
      expect(html.text).to include("Aktiviert").and include("abgelöst").and include("von #{finance}")
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
      expect(html.at_css("details")).to be_nil
      heading = html.at_css("h4")
      expect(heading.text).to eq "Änderungen am Beitrag"
      history = heading.parent
      expect(history.css("h4 ~ .mt-2").size).to eq 1
      expect(history.text).to include("250€ → 300€")
      expect(history.text).not_to include("Neu vereinbart")
      expect(history.text).not_to include("Anderswo")
      expect(html.text).to include("Neue Reduktion planen").and include("Aus aktueller Reduktion planen")
    end

    it "names the reduction by its hint, indented, above the reduced fee" do
      html = section(page_as(Fabricate(Group::Root::Leader.name.to_sym, group: groups(:root)).person))

      line = html.at_css(".ps-3")
      expect(line.text.squish).to start_with("Härtefall (HELP-123)")
      expect(line.text).not_to include("Reduktion")
      expect(html.text).to include("Reduzierter Beitrag")
    end

    describe "installments against the fee" do
      # A custom plan of installments, so their sum is known: the fee is the
      # regular one less the active reduction of 250 €.
      def installments(*euros)
        Wsj27RdpFeeRule.create!(people_id: yp.id, status: "active", activated_at: 1.day.ago,
          custom_installments_starting_year: 2026, custom_installments_cents: euros.map { |eur| eur * 100 })
      end

      def finance_section = section(page_as(Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person))

      let(:fee_eur) { yp.total_fee_cents / 100 }

      it "says nothing when they match" do
        installments(fee_eur - 1000, 1000)

        expect(finance_section.css(".alert-danger, .alert-warning").map(&:text).join)
          .not_to include("Der Ratenplan")
      end

      it "warns in yellow when they bring in more" do
        installments(fee_eur, 100)

        expect(finance_section.at_css(".alert-warning:not(.mt-2.mb-2.py-2)").text)
          .to include("100€ mehr")
      end

      it "reports in red when they bring in less" do
        installments(fee_eur - 300)

        alert = finance_section.at_css(".alert-danger")
        expect(alert.text).to include("es fehlen 300€")
        expect(alert.at_css("i.fa-exclamation-triangle")).to be_present
      end

      it "tells the planned reduction's panel how the installments would fit" do
        installments(fee_eur)

        panel = finance_section.css(".alert-warning").find { |el| el.text.include?("Geplant") }
        expect(panel.text).to include("Nach Aktivierung bringt der Ratenplan 150€ mehr")
      end

      it "warns with a triangle in the planned reduction's panel when the installments would not cover the fee" do
        installments(fee_eur - 300)

        panel = finance_section.css(".alert-warning").find { |el| el.text.include?("Geplant") }
        note = panel.at_css(".text-danger")
        expect(note.text).to include("Nach Aktivierung deckt der Ratenplan den Beitrag nicht")
        expect(note.at_css("i.fa-exclamation-triangle")).to be_present
      end
    end

    it "leaves the changes out without any" do
      html = section(page_as(Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person))

      expect(html.text).not_to include("Änderungen am Beitrag")
    end

    it "heads the section and the installments as h2" do
      body = page_as(Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person)

      expect(Nokogiri::HTML(body).css("h2").map { |h| h.text.strip }).to include("Ratenplan", "Beitragshöhe")
    end

    it "sets the comment in italics, like the comments of the entries" do
      html = section(page_as(Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person))

      expect(html.css(".fee-reduction-comment.fst-italic").map(&:text).map(&:strip))
        .to eq ["Nachweis liegt vor", "Erhöhung"]
    end

    it "morphs page refreshes and keeps the scroll position" do
      body = page_as(Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person)

      expect(body).to include('<meta name="turbo-refresh-method" content="morph">')
        .and include('<meta name="turbo-refresh-scroll" content="preserve">')
    end
  end
end
