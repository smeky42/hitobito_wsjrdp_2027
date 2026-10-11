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
  render_views

  let(:admin) { Fabricate(Group::Root::Admin.name.to_sym, group: groups(:root)).person }
  let(:person) { people(:yp_a_1) }

  def body = Nokogiri::HTML(response.body)

  # The row keys of the rendered page, in order (the widget puts them into the
  # lazy detail frame's DOM id).
  def rendered_ids
    response.body.scan(/bkframe-pref-(\d+)/).flatten.uniq.map(&:to_i)
  end

  def cells(key)
    response.body[%r{<tbody[^>]*>.*</tbody>}m].to_s
      .scan(%r{colkey='#{key}'>(.*?)</td>}m).flatten
      .map { |cell| cell.gsub(/<[^>]+>/, "").strip }
  end

  # The preset toggle links by label, each as its raw <a> tag.
  def preset_links
    response.body.scan(%r{<a[^>]*\bflt-preset\b[^>]*>.*?</a>}m)
      .to_h { |tag| [tag.gsub(/<[^>]+>/, "").strip, tag] }
  end

  def preset_filter(label)
    href = CGI.unescapeHTML(preset_links.fetch(label)[/href="([^"]*)"/, 1].to_s)
    CGI.unescape(href[/[?&]f=([^&]*)/, 1].to_s)
  end

  describe "for an admin" do
    before { sign_in(admin) }

    let!(:assigned) do
      WsjrdpPaymentReference.generate!(1).first.tap { |r| r.update!(status: "assigned", assigned_at: Time.current) }
    end
    let!(:notice) do
      WsjrdpPaymentNotice.create!(subject_id: person.id, amount: "-12.5", description: "Rückzahlung",
        payment_reference: assigned, payment_code: assigned.payment_code)
    end
    let!(:available) { WsjrdpPaymentReference.generate!(2) }

    describe "GET index" do
      it "lists the references newest first, with the counts and the low stock" do
        get :index

        expect(response).to have_http_status(:ok)
        expect(rendered_ids).to eq(available.map(&:id).reverse + [assigned.id])
        expect(cells("payment_code")).to include(assigned.printed_code)
        expect(cells("notice_count")).to eq(%w[0 0 1])
        expect(cells("status")).to eq(%w[verfügbar verfügbar vergeben])
        expect(body.at_css("#payment-references-counts").text).to include("2", "1")
        expect(body.at_css("#payment-references-low-stock")).to be_present
        expect(body.at_css("#payment-references-shown").text).to include("3 Zahlungscodes angezeigt")
      end

      it "leads each row to the code's page and loads it as the row's detail" do
        get :index

        expect(response.body).to include(%(href="#{fin_admin_payment_reference_path(assigned)}"))
        expect(response.body).to include(%(src="#{fin_admin_payment_reference_path(assigned)}))
      end

      it "filters by status through the table's filter param" do
        get :index, params: {f: "!(!(!(st,in,available)))"}

        expect(rendered_ids).to match_array(available.map(&:id))
      end

      it "offers the status as an exclusive group and the codes with notices as a preset" do
        get :index

        expect(preset_links.keys).to include("verfügbar", "vergeben", "ungültig", "mit Zahlungsankündigung")
        get :index, params: {f: preset_filter("mit Zahlungsankündigung")}
        expect(rendered_ids).to eq([assigned.id])
      end

      it "finds a code typed in its printed form" do
        get :index, params: {f: "!(!(!(q,ct,'#{assigned.printed_code.downcase}')))"}

        expect(rendered_ids).to eq([assigned.id])
      end

      it "filters the timestamps as local dates" do
        today = Time.zone.today.iso8601
        get :index, params: {f: "!(!(!(ca,bt,'#{today}','#{today}')))"}
        expect(rendered_ids.size).to eq(3)

        get :index, params: {f: "!(!(!(aa,bl)))"}
        expect(rendered_ids).to match_array(available.map(&:id))
      end

      it "sorts by the notice count" do
        get :index, params: {s: "nc~"}

        expect(rendered_ids.first).to eq(assigned.id)
      end
    end

    describe "GET show" do
      it "renders the code with its notices as a page" do
        get :show, params: {id: assigned.id}

        expect(response).to have_http_status(:ok)
        expect(body.at_css("#payment-reference-#{assigned.id} h1").text).to include(assigned.printed_code)
        fields = body.at_css("#payment-reference-fields").text
        expect(fields).to include(assigned.payment_code, assigned.codeword, "crockford_rs", "vergeben")
        row = body.at_css("#payment-notice-#{notice.id}")
        expect(row.text).to include(person.to_s, "Rückzahlung")
        expect(row.at_css("a")["href"]).to eq(person_path(person))
        expect(body.at_css("turbo-frame#bkframe-pref-#{assigned.id}")).to be_present
      end

      it "answers the row's frame without the layout" do
        request.headers["Turbo-Frame"] = "bkframe-pref-#{assigned.id}"

        get :show, params: {id: assigned.id}

        expect(response).to have_http_status(:ok)
        expect(body.at_css("turbo-frame#bkframe-pref-#{assigned.id}")).to be_present
        expect(body.at_css("#payment-reference-#{assigned.id} h1")).to be_nil
        expect(body.at_css("#payment-reference-#{assigned.id} h2").text).to include(assigned.printed_code)
      end

      it "says when no notice uses the code" do
        get :show, params: {id: available.first.id}

        expect(body.at_css("#payment-reference-no-notices")).to be_present
      end
    end

    describe "POST generate" do
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
        expect { post :generate, params: {count: "x"} }.not_to change(WsjrdpPaymentReference, :count)
      end
    end

    it "applies the filter builder's tree as the filter param" do
      post :apply, params: {filter_json: [[["status", "in", "void"]]].to_json}

      expect(response).to have_http_status(:see_other)
      expect(CGI.unescape(response.location))
        .to match(%r{/fin/admin/payment_references\?f=!\(!\(!\(st,in,'?void'?\)\)\)\z})
    end
  end

  it "is open to the finance manage tier" do
    sign_in(Fabricate(Group::Root::FinanceManager.name.to_sym, group: groups(:root)).person)
    session[:max_finance_permission] = "finance_manage"

    get :index

    expect(response).to have_http_status(:ok)
  end

  describe "for the finance write tier" do
    let(:writer) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }
    let!(:reference) { WsjrdpPaymentReference.generate!(1).first }

    before { sign_in(writer) }

    it "shows the codes and a code's page, without the form making codes" do
      get :index
      expect(response).to have_http_status(:ok)
      expect(body.at_css("#payment-references-generate")).to be_nil

      get :show, params: {id: reference.id}
      expect(response).to have_http_status(:ok)
      expect(body.at_css("h1 .text-muted.fw-light").text).to eq("Zahlungscode ##{reference.id}")
      expect(body.at_css("form.payment-reference-comment-form[hidden] textarea")).to be_present
      expect(body.at_css("[data-payment-reference-comment-edit]")).to be_present
    end

    it "links URLs, e-mail addresses and ticket keys in the comment, with Bearbeiten below it" do
      reference.update!(comment: "Siehe HELP-123, kontakt@example.org und https://example.org/info")

      get :show, params: {id: reference.id}

      view = body.at_css(".payment-reference-comment-view")
      expect(view.css("a").pluck("href")).to include("https://helpdesk.worldscoutjamboree.de/browse/HELP-123",
        "mailto:kontakt@example.org", "https://example.org/info")
      expect(view.at_css("> .text-break")).to be_present
      expect(view.at_css("> button[data-payment-reference-comment-edit]")).to be_present
    end

    it "refuses making codes" do
      expect { post :generate, params: {count: "1"} }.to raise_error(CanCan::AccessDenied)
      expect(WsjrdpPaymentReference.count).to eq(1)
    end

    it "saves the comment and answers with the code's page" do
      patch :update, params: {id: reference.id, wsjrdp_payment_reference: {comment: "Für die Rückzahlung reserviert"}}

      expect(reference.reload.comment).to eq("Für die Rückzahlung reserviert")
      expect(response).to redirect_to(fin_admin_payment_reference_path(reference))
    end

    it "saves the comment from a row's detail and renders that frame again" do
      request.headers["Turbo-Frame"] = "bkframe-pref-#{reference.id}"
      patch :update, params: {id: reference.id, wsjrdp_payment_reference: {comment: ""}}
      expect(response).to redirect_to(fin_admin_payment_reference_path(reference))

      get :show, params: {id: reference.id}
      expect(body.at_css("turbo-frame#bkframe-pref-#{reference.id}")).to be_present
      expect(body.at_css("h2 .text-muted.fw-light").text).to eq("Zahlungscode ##{reference.id}")
    end

    it "takes nothing but the comment" do
      patch :update, params: {id: reference.id, wsjrdp_payment_reference: {comment: "x", status: "void"}}

      expect(reference.reload).to have_attributes(comment: "x", status: "available")
    end
  end

  it "lets an admin edit the comment" do
    sign_in(admin)
    reference = WsjrdpPaymentReference.generate!(1).first

    patch :update, params: {id: reference.id, wsjrdp_payment_reference: {comment: "Admin"}}

    expect(reference.reload.comment).to eq("Admin")
  end

  it "refuses the read and audit tiers" do
    extern = Group::Extern.create!(name: "Extern", parent: groups(:root))
    sign_in(Fabricate(Group::Extern::FinanceAuditor.name.to_sym, group: extern).person)
    reference = WsjrdpPaymentReference.generate!(1).first

    expect { get :index }.to raise_error(CanCan::AccessDenied)
    expect { get :show, params: {id: reference.id} }.to raise_error(CanCan::AccessDenied)
    expect { patch :update, params: {id: reference.id, wsjrdp_payment_reference: {comment: "x"}} }
      .to raise_error(CanCan::AccessDenied)
    expect(reference.reload.comment).to eq("")
  end
end
