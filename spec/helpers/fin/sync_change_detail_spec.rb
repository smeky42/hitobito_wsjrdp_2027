# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# One change of a sync run through the detail kit: the label of the table,
# old → new, the chip of a notice at its column. Every value is invented.
describe "the change detail of a sync run", type: :helper do
  let(:ctx) { Fin::AttrFormatContext.regular }
  let(:notice) do
    Wsjrdp::Sync::Plan::Warning.new(level: "hint", code: "unknown_department_archived",
      message: "Unbekannt", items: {"t-1" => "Team X"})
  end

  def record(action, values, notices: [])
    change = Wsjrdp::Sync::Plan::Change.new(action: action, key: "t-1", label: "Team X", values: values)
    Fin::SyncChangeRecord.new(change, notices, {"unknown_department_archived" => "moss_department_uuid"}, {}, model: MossTeam)
  end

  it "labels a column as the table does, its name as the tooltip" do
    detail = helper.fin_format_attr(record("create", {"moss_department_uuid" => "d-1"}), :moss_department_uuid, ctx)
    expect(detail.label).to eq(MossTeam.human_attribute_name("moss_department_uuid"))
    expect(detail.tooltip).to eq("moss_department_uuid")
    expect(detail.value).to eq("d-1")
  end

  it "shows an update as old → new" do
    detail = helper.fin_format_attr(record("update", {"name" => ["Alt", "Neu"]}), :name, ctx)
    expect(detail.value).to eq("Alt → Neu")
  end

  it "marks a field an update sets for the first time" do
    detail = helper.fin_format_attr(record("update", {"name" => [nil, "Neu"]}), :name, ctx)
    expect(Nokogiri::HTML.fragment(detail.value).css(".badge").text).to eq("neu")
  end

  describe "the targets of a row" do
    def change(action, key, values, ref: nil)
      target, column = key.start_with?("person:") ? ["Person", "additional_info"] : ["MossUser", nil]
      Wsjrdp::Sync::Plan::Change.new(action: action, key: key, label: "Ben Muster", values: values,
        target: target, target_column: column, ref: ref)
    end

    def chips(plan)
      Fin::SyncChangesColumns.rows(plan).map do |row|
        Nokogiri::HTML.fragment(helper.fin_sync_target_chips(row, MossUser)).css(".badge").map(&:text)
      end
    end

    it "puts a person's fields into the row of their Moss user, the mixed states apart" do
      plan = Wsjrdp::Sync::Plan.new(changes: [
        change("create", "u-1", {"email" => "ben@example.org"}),
        change("update", "person:7", {"moss_status" => [nil, "ACTIVE"], "moss_team" => [nil, "T"],
                                      "moss_roles" => [["USER"], ["ADMIN"]]}, ref: "u-1")
      ])
      expect(chips(plan)).to eq([["MossUser neu", "Person: 2 Felder neu", "Person: 1 Feld geändert"]])
    end

    it "says the Moss user is unchanged when only its person changes" do
      plan = Wsjrdp::Sync::Plan.new(changes: [change("update", "person:7", {"moss_status" => %w[INVITED ACTIVE]}, ref: "u-1")])
      expect(chips(plan)).to eq([["MossUser unverändert", "Person: 1 Feld geändert"]])
    end

    it "stores the target, and leaves out what is not set" do
      plan = Wsjrdp::Sync::Plan.new(changes: [change("create", "u-1", {"email" => "x"})])
      expect(plan.to_h["changes"].first.keys).to eq(%w[action key label values target])
    end

    it "keeps the digest of a plan stored without targets" do
      stored = {"changes" => [{"action" => "create", "key" => "u-1", "label" => "Ben", "values" => {"email" => "x"}}],
                "warnings" => []}
      expect(Wsjrdp::Sync::Plan.from_h(stored).to_h).to eq(stored)
    end

    it "names the model and the column in the heading of a person's fields" do
      heading = helper.fin_sync_change_heading(change("update", "person:7", {"moss_status" => %w[A B]}), Person, nil)
      expect(Nokogiri::HTML.fragment(heading).text).to eq("Person · Ben Muster · additional_info")
    end
  end

  it "puts the chip of a notice at its column only" do
    rec = record("create", {"name" => "Team X", "moss_department_uuid" => "d-1"}, notices: [notice])
    expect(helper.fin_format_attr(rec, :moss_department_uuid, ctx).value).to include("badge")
    expect(helper.fin_format_attr(rec, :name, ctx).value).not_to include("badge")
    expect(rec.notices(nil)).to be_empty
  end

  it "lists a notice about an unchanged Moss user below its person's fields, with the user's text" do
    person = Wsjrdp::Sync::Plan::Change.new(action: "update", key: "person:7", label: "Ben Muster",
      values: {"moss_status" => %w[INVITED ACTIVE]}, target: "Person", target_column: "additional_info", ref: "u-1")
    without_contract = Wsjrdp::Sync::Plan::Warning.new(level: "important", code: "moss_user_without_contract",
      message: "1 Benutzer", items: {"u-1" => "Ben Muster → Person: Ben Muster"})
    row = Fin::SyncChangesColumns.rows(Wsjrdp::Sync::Plan.new(changes: [person], warnings: [without_contract])).sole
    html = helper.render("fin/sync_runs/change_detail", row: row, fields: Wsjrdp::Sync::MossApi::Users.notice_fields,
      people: {}, records: {}, model: MossUser, ctx: ctx)
    listed = Nokogiri::HTML.fragment(html).css("p").select { |p| p.css(".badge").any? }
    expect(listed.map { |p| p.text.squish }).to eq(["Person ohne Vertrag Ben Muster → Person: Ben Muster"])
  end

  it "renders through fin_detail" do
    rec = record("create", {"name" => "Team X"})
    html = helper.fin_detail(rec, ctx) { |d| d.attrs(*rec.columns) }
    expect(html).to include("Team X")
  end

  it "links a person of a notice and keeps what the notice says of them" do
    person = people(:ul_a_1)
    html = helper.fin_sync_notice_item(person, "#{person} · Moss-E-Mail: weg@example.org")
    fragment = Nokogiri::HTML.fragment(html)
    expect(fragment.css("a").first["href"]).to eq(helper.person_path(person))
    expect(fragment.css(".text-muted").text).to eq("Moss-E-Mail: weg@example.org")
  end
end
