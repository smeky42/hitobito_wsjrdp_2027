# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# Zahlungscodes, the third tab of the Verwaltung area
# (/fin/admin/payment_references): the references as an expandable table, the
# stock and making codes for it, and a code's page with the notices using it.
describe Fin::PaymentReferencesController do
  before_all(setup_fixtures: true) {}

  let_it_be(:admin) { Fabricate(Group::Root::Admin.name.to_sym, group: groups(:root)).person }
  let_it_be(:writer) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }
  let(:person) { people(:yp_a_1) }

  let_it_be(:assigned) do
    WsjrdpPaymentReference.generate!(1).first.tap { |r| r.update!(status: "assigned", assigned_at: Time.current) }
  end
  let_it_be(:notice) do
    WsjrdpPaymentNotice.create!(subject_id: people(:yp_a_1).id, amount: "-12.5", description: "Rückzahlung",
      payment_reference: assigned, payment_code: assigned.payment_code)
  end
  let_it_be(:available) { WsjrdpPaymentReference.generate!(2) }

  def listed = controller.send(:payment_references).page.to_a

  def listed_ids = listed.map(&:id)

  describe "GET index" do
    before { sign_in(admin) }

    def index(filter) = get(:index, params: {f: filter})

    it "lists the references newest first, with their notice counts and the stock" do
      get :index

      expect(listed_ids).to eq(available.map(&:id).reverse + [assigned.id])
      expect(listed.map(&:notice_count)).to eq([0, 0, 1])
      expect(controller.send(:counts)).to eq("available" => 2, "assigned" => 1)
    end

    it "filters by status" do
      index("!(!(!(st,in,available)))")

      expect(listed_ids).to match_array(available.map(&:id))
    end

    it "filters the codes with notices" do
      index("!(!(!(nc,nz)))")

      expect(listed_ids).to eq([assigned.id])
    end

    it "finds a code typed in its printed form" do
      index("!(!(!(q,ct,'#{assigned.printed_code.downcase}')))")

      expect(listed_ids).to eq([assigned.id])
    end

    it "filters the creation time as a local date" do
      today = Time.zone.today.iso8601
      index("!(!(!(ca,bt,'#{today}','#{today}')))")

      expect(listed_ids.size).to eq(3)
    end

    it "filters a blank assignment time" do
      index("!(!(!(aa,bl)))")

      expect(listed_ids).to match_array(available.map(&:id))
    end

    it "sorts by the notice count" do
      get :index, params: {s: "nc~"}

      expect(listed_ids.first).to eq(assigned.id)
    end
  end

  describe "rendered" do
    render_views

    def body = Nokogiri::HTML(response.body)

    it "shows an admin the stock with its low-stock warning and the form making codes" do
      sign_in(admin)

      get :index

      expect(body.at_css("#payment-references-low-stock")).to be_present
      expect(body.at_css("#payment-references-generate")).to be_present
      expect(response.body).to include(%(href="#{fin_admin_payment_reference_path(assigned)}"))
    end

    it "shows the write tier the codes without the form making codes" do
      sign_in(writer)

      get :index

      expect(body.at_css("#payment-references-generate")).to be_nil
    end

    it "renders the code with its notices as a page" do
      sign_in(admin)

      get :show, params: {id: assigned.id}

      expect(body.at_css("#payment-reference-#{assigned.id} h1").text).to include(assigned.printed_code)
      expect(body.at_css("#payment-notice-#{notice.id} a")["href"]).to eq(person_path(person))
      expect(body.at_css("turbo-frame#bkframe-pref-#{assigned.id}")).to be_present
    end

    it "answers the row's frame without the layout" do
      sign_in(admin)
      request.headers["Turbo-Frame"] = "bkframe-pref-#{assigned.id}"

      get :show, params: {id: assigned.id}

      expect(body.at_css("turbo-frame#bkframe-pref-#{assigned.id}")).to be_present
      expect(body.at_css("#payment-reference-#{assigned.id} h1")).to be_nil
      expect(response.body).not_to include("<html")
    end

    it "offers the write tier the comment form, with links in the comment" do
      assigned.update!(comment: "Siehe HELP-123, kontakt@example.org und https://example.org/info")
      sign_in(writer)

      get :show, params: {id: assigned.id}

      expect(body.at_css("form.payment-reference-comment-form textarea")).to be_present
      expect(body.css(".payment-reference-comment-view a").pluck("href"))
        .to include("https://helpdesk.worldscoutjamboree.de/browse/HELP-123",
          "mailto:kontakt@example.org", "https://example.org/info")
    end
  end

  describe "POST generate" do
    before { sign_in(admin) }

    it "makes the codes asked for" do
      expect { post :generate, params: {count: "3"} }.to change { WsjrdpPaymentReference.available.count }.by(3)
      expect(response).to redirect_to(fin_admin_payment_references_path)
      expect(WsjrdpPaymentReference.distinct.pluck(:origin)).to eq(%w[wagon])
    end

    it "fills the pool without a count" do
      stub_const("WsjrdpPaymentReference::POOL_SIZE", 4)

      post :generate

      expect(WsjrdpPaymentReference.available.count).to eq(4)
    end

    it "refuses a count out of range" do
      expect { post :generate, params: {count: "0"} }.not_to change(WsjrdpPaymentReference, :count)
      expect(flash[:alert]).to be_present
    end

    it "is refused to the write tier" do
      sign_in(writer)

      expect { post :generate, params: {count: "1"} }.to raise_error(CanCan::AccessDenied)
    end
  end

  it "applies the filter builder's tree as the filter param" do
    sign_in(admin)

    post :apply, params: {filter_json: [[["status", "in", "void"]]].to_json}

    expect(response).to have_http_status(:see_other)
    expect(CGI.unescape(response.location))
      .to match(%r{/fin/admin/payment_references\?f=!\(!\(!\(st,in,'?void'?\)\)\)\z})
  end

  describe "PATCH update" do
    def update(attrs) = patch(:update, params: {id: assigned.id, wsjrdp_payment_reference: attrs})

    it "saves the comment for the write tier and takes nothing else" do
      sign_in(writer)

      update(comment: "Für die Rückzahlung reserviert", status: "void")

      expect(assigned.reload).to have_attributes(comment: "Für die Rückzahlung reserviert", status: "assigned")
      expect(response).to redirect_to(fin_admin_payment_reference_path(assigned))
    end

    it "lets an admin edit the comment" do
      sign_in(admin)

      update(comment: "Admin")

      expect(assigned.reload.comment).to eq("Admin")
    end
  end

  it "is open to the finance manage tier" do
    sign_in(Fabricate(Group::Root::FinanceManager.name.to_sym, group: groups(:root)).person)
    session[:max_finance_permission] = "finance_manage"

    get :index

    expect(response).to have_http_status(:ok)
  end

  it "refuses the read and audit tiers" do
    extern = Group::Extern.create!(name: "Extern", parent: groups(:root))
    sign_in(Fabricate(Group::Extern::FinanceAuditor.name.to_sym, group: extern).person)

    expect { get :index }.to raise_error(CanCan::AccessDenied)
    expect { get :show, params: {id: assigned.id} }.to raise_error(CanCan::AccessDenied)
    expect { patch :update, params: {id: assigned.id, wsjrdp_payment_reference: {comment: "x"}} }
      .to raise_error(CanCan::AccessDenied)
    expect(assigned.reload.comment).to eq("")
  end
end
