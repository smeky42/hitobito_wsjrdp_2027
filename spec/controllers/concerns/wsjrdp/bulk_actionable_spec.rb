# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The generic half of a bulk action: the posted selection within the scope,
# the authorization, the transaction and the flash. The rows are people, the
# actions write their nickname; what a real action does is its host's.
describe Wsjrdp::BulkActionable, type: :controller do
  let(:actions) do
    Wsjrdp::BulkActions.define(noun: {one: "Person", many: "Personen"}) do |a|
      a.action key: "nick", label: "Spitzname setzen", icon: :tag, apply: :bulk_nick,
        param: {name: :nick, label: "Spitzname", options: :nick_options},
        hint: {one: "1", many: "%{count}"}, done: "%{count} Personen: %{target}."
      # Changes only the people whose last name is not "Keep"; warns about
      # those without a first name.
      a.action key: "split", label: "Teilweise", icon: :tag, apply: :bulk_nick, partition: :split_people,
        hint: {one: "1", many: "%{count}"}, done: "%{count} geändert."
      # No rule grants it, so nobody may run it.
      a.action key: "forbidden", label: "Verboten", icon: :lock, apply: :bulk_nick,
        hint: {one: "1", many: "%{count}"}, done: "%{count}", authorize: [:bulk_spec, :nobody]
    end
  end

  controller(ApplicationController) do
    include Wsjrdp::BulkActionable

    skip_authorization_check

    def bulk
      scope = Person.where(id: params[:scope_ids].to_s.split(",").map(&:to_i))
      atoms = ->(relation, keys) { relation.where(last_name: keys) }
      flash.update(run_bulk_action(self.class.spec_actions, scope: scope, atoms: atoms))
      head :ok
    end

    def preview
      scope = Person.where(id: params[:scope_ids].to_s.split(",").map(&:to_i))
      render_bulk_preview(self.class.spec_actions, scope: scope, order: {id: :asc}, limit: params[:limit].to_i,
        columns: ->(_view) { [{key: "name", label: "Name", cell: ->(person) { person.last_name }}] })
    end

    private

    def nick_options = [["Kurz", "kurz"], ["Lang", "lang"]]

    def split_people(selected, _value)
      keep = selected.where(nickname: "Keep")
      Wsjrdp::BulkActions::Partition.new(affected: selected.where.not(id: keep.select(:id)),
        columns: [{label: "Neu", cell: ->(_person) { "split" }}],
        groups: [Wsjrdp::BulkActions::Group.new(rows: keep, text: "%{count} bleiben wie sie sind.", warning: true)])
    end

    def bulk_nick(ids, value)
      raise ArgumentError, "Kein gültiger Spitzname: #{value}" if value == "boom"

      Person.where(id: ids).update_all(nickname: value)
    end
  end

  before do
    defined = actions
    controller.class.define_singleton_method(:spec_actions) { defined }
    routes.draw do
      post "bulk" => "anonymous#bulk"
      post "preview" => "anonymous#preview"
    end
    sign_in(people(:admin))
  end

  let(:people_in_scope) { [people(:admin), people(:cmt_leader)] }
  let(:scope_ids) { people_in_scope.map(&:id).join(",") }
  let(:outsider) { people(:yp_a_1) }

  it "runs the action on the posted ids within the scope and says how many" do
    post :bulk, params: {bulk_action: "nick", nick: "kurz", scope_ids: scope_ids,
                         ids: [people(:admin).id, outsider.id]}

    expect(flash[:notice]).to eq("1 Personen: Kurz.")
    expect(people(:admin).reload.nickname).to eq("kurz")
    expect(outsider.reload.nickname).not_to eq("kurz")
  end

  it "takes every row of the scope with select_all=1, the atoms' rows otherwise" do
    post :bulk, params: {bulk_action: "nick", nick: "lang", scope_ids: scope_ids, select_all: "1"}
    expect(people_in_scope.map { |person| person.reload.nickname }).to eq(%w[lang lang])

    post :bulk, params: {bulk_action: "nick", nick: "kurz", scope_ids: scope_ids,
                         select_all: people(:cmt_leader).last_name}
    expect(people(:cmt_leader).reload.nickname).to eq("kurz")
    expect(people(:admin).reload.nickname).to eq("lang")
  end

  it "says so for nothing selected, an unknown action and a refused value" do
    post :bulk, params: {bulk_action: "nick", nick: "kurz", scope_ids: scope_ids}
    expect(flash[:alert]).to eq("Keine Personen ausgewählt.")

    post :bulk, params: {bulk_action: "nope", scope_ids: scope_ids, select_all: "1"}
    expect(flash[:alert]).to eq("Unbekannte Aktion.")

    post :bulk, params: {bulk_action: "nick", nick: "boom", scope_ids: scope_ids, select_all: "1"}
    expect(flash[:alert]).to eq("Kein gültiger Spitzname: boom")
  end

  describe "the preview" do
    render_views

    it "lists the rows the selection resolves to, at most the limit, and how many more" do
      post :preview, params: {scope_ids: scope_ids, select_all: "1", limit: 1}

      html = Nokogiri::HTML.fragment(response.body)
      expect(response.body).not_to include("<html")
      expect(html.at_css(".bk-bulk-preview-head").text.squish).to eq("Betrifft 2 Personen")
      expect(html.css(".bk-bulk-preview-list tbody tr").size).to eq(1)
      expect(html.at_css(".bk-bulk-preview-list thead th").text).to eq("Name")
      expect(html.text).to include("… und 1 weitere")

      post :preview, params: {scope_ids: scope_ids, ids: [people(:admin).id, outsider.id], limit: 200}
      expect(Nokogiri::HTML.fragment(response.body).css("tbody tr td").map(&:text))
        .to eq([people(:admin).last_name])
    end
  end

  describe "an action with a partition" do
    render_views

    before { people(:cmt_leader).update_columns(nickname: "Keep") }

    it "runs on the rows it changes only" do
      post :bulk, params: {bulk_action: "split", scope_ids: scope_ids, select_all: "1"}

      expect(flash[:notice]).to eq("1 geändert.")
      expect(people(:admin).reload.nickname).to be_nil
      expect(people(:cmt_leader).reload.nickname).to eq("Keep")
    end

    it "previews the rows it changes with its columns, and the rest as a warning with their rows" do
      post :preview, params: {bulk_action: "split", scope_ids: scope_ids, select_all: "1", limit: 200}

      html = Nokogiri::HTML.fragment(response.body)
      expect(html.at_css(".bk-bulk-preview-head").text.squish).to eq("Betrifft 1 Person")
      expect(html.css(".bk-bulk-preview-list").first.css("thead th").map(&:text)).to eq(%w[Name Neu])
      warning = html.at_css(".alert-warning")
      expect(warning.text).to include("1 bleiben wie sie sind.")
      expect(warning.css("tbody td").map(&:text)).to include(people(:cmt_leader).last_name)
    end

    it "says so when it changes none of the selected rows" do
      post :bulk, params: {bulk_action: "split", scope_ids: people(:cmt_leader).id.to_s, select_all: "1"}

      expect(flash[:alert]).to eq("Keine der ausgewählten Personen ist betroffen.")
    end
  end

  it "refuses an action the user may not run, writing nothing" do
    expect { post :bulk, params: {bulk_action: "forbidden", scope_ids: scope_ids, select_all: "1"} }
      .to raise_error(CanCan::AccessDenied)
    expect(people(:admin).reload.nickname).to be_blank
  end
end
