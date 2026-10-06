# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# Planning, activating and discarding a total fee reduction from the
# "Beitragshöhe" section of the Beitrag page. They change the fee, so they need
# :update_finance; the person log records what took effect, not the plans.
describe Person::FeeReductionController, type: :controller do
  let(:finance) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }
  let(:leader) { Fabricate(Group::Root::Leader.name.to_sym, group: groups(:root)).person }
  let(:person) { people(:yp_a_1) }
  let(:planned_keys) { %w[planned_total_fee_reduction planned_total_fee_reduction_issue planned_total_fee_reduction_hint planned_total_fee_reduction_comment] }

  def plan(commit_action: nil, format: nil, target_turbo_frame: nil, **attrs)
    top = {person_id: person.id, commit_action: commit_action, target_turbo_frame: target_turbo_frame}.compact
    values = {planned_total_fee_reduction_issue: "HELP-2", planned_total_fee_reduction: "500",
              planned_total_fee_reduction_hint: "Härtefall", planned_total_fee_reduction_comment: "Vereinbarung"}
    put :update, format: format, params: top.merge(person: values.merge(attrs))
  end

  describe "as finance" do
    before { sign_in(finance) }

    it "stores a plan without touching the fee or the log" do
      # The fixture fills in its payment role and pronoun on its first save;
      # that change must not count as the plan's.
      person.save!
      with_versioning do
        expect { plan(planned_total_fee_reduction: "250,50") }.not_to change { person.versions.count }
      end

      expect(response).to redirect_to(person_fee_path(person))
      person.reload
      expect(person.planned_total_fee_reduction).to eq BigDecimal("250.5")
      expect(person.planned_total_fee_reduction_issue).to eq "HELP-2"
      expect(person.wsjrdp_total_fee_reduction).to eq 0
    end

    it "refuses an amount that is no amount or more than the regular fee, keeping what was typed" do
      max_eur = person.total_fee_eur.to_i
      ["", "0", "abc", (max_eur + 1).to_s].each do |amount|
        plan(planned_total_fee_reduction: amount)

        expect(response).to have_http_status(422)
        expect(person.reload.planned_total_fee_reduction).to be_nil
      end
    end

    it "activates the plan: all four values take effect, the plan is gone, the log shows the effect" do
      plan

      with_versioning { post :activate, params: {person_id: person.id} }

      expect(response).to redirect_to(person_fee_path(person))
      person.reload
      expect(person).to have_attributes(wsjrdp_total_fee_reduction: 500, wsjrdp_total_fee_reduction_issue: "HELP-2",
        wsjrdp_total_fee_reduction_hint: "Härtefall", wsjrdp_total_fee_reduction_comment: "Vereinbarung")
      expect(person.additional_info.keys & planned_keys).to be_empty
      changes = person.versions.reorder(:id).last.changeset
      expect(changes.keys).to include("wsjrdp_total_fee_reduction", "wsjrdp_total_fee_reduction_issue")
      expect(changes.keys & planned_keys).to be_empty
    end

    it "saves and activates the plan in one go from the form" do
      plan(planned_total_fee_reduction: "300", commit_action: "activate")

      person.reload
      expect(person.wsjrdp_total_fee_reduction).to eq 300
      expect(person.planned_total_fee_reduction).to be_nil
    end

    it "drops the plan from the form, whatever the form holds" do
      plan

      plan(planned_total_fee_reduction: "", commit_action: "discard")

      expect(response).to redirect_to(person_fee_path(person))
      expect(person.reload.additional_info.keys & planned_keys).to be_empty
    end

    it "refreshes the page in place after saving from the form's frame, the notice for the section" do
      plan(format: :turbo_stream)

      expect(response.media_type).to eq "text/vnd.turbo-stream.html"
      expect(response.body).to include('action="refresh"')
      expect(flash[:fee_reduction_notice]).to eq("person_id" => person.id, "text" => described_class::PLAN_SAVED)
      expect(flash[:notice]).to be_nil
    end

    it "reloads the whole page, keeping the scroll position, after a change from the Reduktionen list" do
      plan
      post :activate, params: {person_id: person.id, context: "fin"}, format: :turbo_stream

      expect(response.body).to include('action="reload_keep_scroll"')
      expect(person.reload.wsjrdp_total_fee_reduction).to eq 500
    end

    it "keeps the comment out of the person log" do
      person.save!
      plan(planned_total_fee_reduction_comment: "Nur für die Buchhaltung")

      with_versioning { post :activate, params: {person_id: person.id} }

      expect(person.reload.wsjrdp_total_fee_reduction_comment).to eq "Nur für die Buchhaltung"
      expect(person.versions.last.object_changes).not_to include("comment")
      expect(person.versions.last.object.to_s).not_to include("wsjrdp_total_fee_reduction_comment")
    end

    it "activates nothing without a plan" do
      post :activate, params: {person_id: person.id}

      expect(flash[:fee_reduction_notice]["text"]).to include("keine Beitragsreduktion geplant")
      expect(person.reload.wsjrdp_total_fee_reduction).to eq 0
    end

    it "discards the plan and leaves the active reduction alone" do
      person.update!(wsjrdp_total_fee_reduction: 100)
      plan

      post :discard, params: {person_id: person.id}

      person.reload
      expect(person.wsjrdp_total_fee_reduction).to eq 100
      expect(person.additional_info.keys & planned_keys).to be_empty
    end

    describe "the form" do
      render_views

      it "passes the list's context on to the form and its buttons" do
        get :edit, params: {person_id: person.id, mode: "new", context: "fin"}, format: :turbo_stream

        form = Nokogiri::HTML(Nokogiri::HTML(response.body).at_css("template").inner_html)
        expect(form.at_css("input[name=context]")["value"]).to eq "fin"
        expect(form.at_css("a[href*='buttons']")["href"]).to include("context=fin")
      end

      it "answers a refused plan in place of the buttons, the amount as typed and the error on top" do
        plan(planned_total_fee_reduction: "99999,5", format: :turbo_stream)

        expect(response).to have_http_status(422)
        stream = Nokogiri::HTML(response.body).at_css("turbo-stream[action=update][target=fee_reduction_actions_#{person.id}]")
        form = Nokogiri::HTML(stream.at_css("template").inner_html)
        expect(form.at_css(".alert-danger").text).to include("Betrag muss größer als 0")
        expect(form.at_css("input[name='person[planned_total_fee_reduction]']")["value"]).to eq "99999,5"
      end

      it "brings the section's buttons back in place of the form on Abbrechen" do
        get :buttons, params: {person_id: person.id}, format: :turbo_stream

        stream = Nokogiri::HTML(response.body).at_css("turbo-stream[action=update][target=fee_reduction_actions_#{person.id}]")
        expect(stream.at_css("template").inner_html).to include("Neue Reduktion planen")
      end

      it "sends the form as a stream in place of the buttons" do
        get :edit, params: {person_id: person.id, mode: "new"}, format: :turbo_stream

        stream = Nokogiri::HTML(response.body).at_css("turbo-stream[action=update][target=fee_reduction_actions_#{person.id}]")
        expect(stream.at_css("template").inner_html).to include("Beitragsreduktion planen")
      end

      it "labels the fields briefly, marks the amount required and explains hint and comment" do
        get :edit, params: {person_id: person.id, mode: "new"}

        doc = Nokogiri::HTML(response.body)
        expect(doc.css(".fee-reduction-form label").map { |l| l.text.strip.delete("*") })
          .to eq %w[Betrag Kurzhinweis Vorgang Kommentar]
        expect(doc.at_css("label[for='person_planned_total_fee_reduction']")["class"]).to include("required")
        expect(doc.text).to include("Erscheint im Vertrag").and include("Nur sichtbar für Personen mit Buchhaltungs-Rechten")
        expect(doc.css("button[name=commit_action]").pluck("value")).to eq %w[save activate discard]
      end

      it "starts from the active reduction" do
        person.update!(wsjrdp_total_fee_reduction: 300, wsjrdp_total_fee_reduction_hint: "rdp Delegate")

        get :edit, params: {person_id: person.id, mode: "from_active"}

        expect(response.body).to include("value=\"300,00\"").and include("value=\"rdp Delegate\"")
      end

      it "starts blank for a new plan, whatever is planned" do
        plan

        get :edit, params: {person_id: person.id, mode: "new"}

        expect(response.body).not_to include("value=\"500,00\"")
      end
    end
  end

  it "refuses every action to a leader, who only sees the section" do
    sign_in(leader)

    expect { plan }.to raise_error(CanCan::AccessDenied)
    expect { post :activate, params: {person_id: person.id} }.to raise_error(CanCan::AccessDenied)
    expect { post :discard, params: {person_id: person.id} }.to raise_error(CanCan::AccessDenied)
    expect { get :edit, params: {person_id: person.id} }.to raise_error(CanCan::AccessDenied)
  end
end
