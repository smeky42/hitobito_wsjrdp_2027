# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# A whole run of the Synchronisation with a fake Moss client: no request
# leaves the process. The data is made up (spec/fixtures/files/moss).
describe Wsjrdp::Sync do
  include SyncSpecHelpers

  let(:admin) { people(:cmt_leader) }
  let(:organisation_keys) { [Wsjrdp::Sync::MossApi::Departments.key, teams_key, users_key] }
  let(:users_key) { Wsjrdp::Sync::MossApi::Users.key }
  let(:teams_key) { Wsjrdp::Sync::MossApi::Teams.key }

  def start(keys = organisation_keys, now: Time.zone.parse("2026-11-23 14:25:01 UTC"))
    Wsjrdp::Sync::Start.new(source: :moss_api, selection: keys, client: client, actor: admin,
      now: now).call
  end

  def apply(run, confirmed: true, warnings_confirmed: false)
    Wsjrdp::Sync::Apply.new(run.reload, actor: admin, confirmed: confirmed, warnings_confirmed: warnings_confirmed).call
  end

  def part(run, key) = run.parts.reload.find { |record| record.part_key == key }

  def codes(run, key) = part(run, key).plan_object.warnings.map(&:code)

  describe "the tree" do
    it "adds what a part depends on, in the order of the parts" do
      expect(described_class.expand([users_key])).to eq(organisation_keys)
      expect(described_class.expand([Wsjrdp::Sync::MossApi::Departments.key]))
        .to eq([Wsjrdp::Sync::MossApi::Departments.key])
    end

    it "groups the parts by their keys under Moss API" do
      api = described_class.tree.children.sole
      organisation, master_data = api.children

      expect([api.label, organisation.label, master_data.label]).to eq(["Moss API", "Organisationsstruktur", "Stammdaten"])
      expect((organisation.children + master_data.children).map(&:part)).to eq(described_class.parts_of(:moss_api))
    end
  end

  describe "a first run" do
    it "plans without writing, then writes once confirmed" do
      run = start

      expect(run.status).to eq("planned")
      expect(run.parts.map(&:counts)).to eq([{"create" => 2}, {"create" => 3}, {"create" => 4}])
      expect(MossUser.count).to eq(0)

      expect { apply(run, confirmed: false) }.to raise_error(Wsjrdp::Sync::Apply::Refused, "not_confirmed")

      apply(run)

      expect(run.reload).to have_attributes(status: "applied", confirmed_by: admin)
      expect(MossDepartment.count).to eq(2)
      expect(MossTeam.pluck(:status)).to contain_exactly("ACTIVE", "ARCHIVED", "ACTIVE")
      user = MossUser.find_by!(email: "ben.muster@example.org")
      expect(user).to have_attributes(first_name: "Ben", roles: %w[TEAMLEAD USER],
        moss_created_at: Time.utc(2025, 9, 2, 10), last_seen_at: be_present)
      expect(MossUser.find_by!(email: "eingeladen@example.org").first_name).to be_nil
      expect { apply(run) }.to raise_error(Wsjrdp::Sync::Apply::Refused, "not_open")
    end

    it "counts the rows written and times every phase, per part and for the run" do
      run = start
      expect(WsjrdpSyncRunPart.last_started_at(users_key)).to eq(part(run, users_key).fetch_started_at)
      expect(WsjrdpSyncRunPart.last_applied_at(users_key)).to be_nil

      apply(run)

      expect(part(run, users_key).stats)
        .to eq("modified_rows" => {"inserted" => 4, "updated" => 0, "deleted" => 0, "soft_deleted" => 0})
      expect(run.reload.modified_rows["inserted"]).to eq(2 + 3 + 4)
      expect(run.timings.pluck("phase")).to eq(%w[start apply])
      expect(part(run, users_key).timings.pluck("phase")).to eq(%w[fetch plan apply])
      expect(run.timings.first).to include("started_at", "finished_at", "duration_ms", "status" => "succeeded")
      expect(WsjrdpSyncRunPart.last_applied_at(users_key)).to be_present
    end

    it "hints at dangling references without asking twice, and keeps the data in files named by the start in UTC" do
      run = start

      expect(codes(run, users_key)).to contain_exactly("unknown_manager", "without_person", "without_person_deactivated")
      expect(run.warnings?).to be(false)
      manager = part(run, users_key).plan_object.warnings.find { |notice| notice.code == "unknown_manager" }
      expect(manager.items.values)
        .to eq(["Cem Ohneteam · Status: DEACTIVATED · E-Mail: ohne.team@example.org → b0000000-0000-4000-8000-000000000099"])
      names = part(run, users_key).files.pluck("name")

      expect(names).to eq(%w[data-users data-paging meta].map { |file| "20261123T142501Z_run-#{run.id}_#{users_key}.#{file}.json" })
      expect(Wsjrdp::Sync::Files.data(part(run, users_key).files)["users"].size).to eq(4)
    end

    it "keeps the credential it read with" do
      credential = instance_double(Wsjrdp::Credentials::Credential, account_key: "default", version_id: nil,
        kind: Wsjrdp::Credentials::Kinds.current["moss_api"])
      run = Wsjrdp::Sync::Start.new(source: :moss_api, selection: [users_key], client: client, actor: admin,
        credential: credential, credential_source: "YAML").call

      expect(run).to have_attributes(credential_source: "YAML", credential_kind: "moss_api", account_key: "default",
        credential_id: nil)
    end

    it "names a record without a name by its UUID" do
      department = lists["departments"].first
      department["name"] = nil
      department["ownerId"] = "b0000000-0000-4000-8000-0000000000ff"

      notice = part(start, Wsjrdp::Sync::MossApi::Departments.key).plan_object.warnings.sole

      expect(notice.items).to eq(department["id"] => "#{department["id"]} → b0000000-0000-4000-8000-0000000000ff")
    end

    it "makes what concerns archived teams or deactivated users a mere hint" do
      lists["teams"].each { |team| team["departmentId"] = "d0000000-0000-4000-8000-0000000000ff" }

      levels = part(start, teams_key).plan_object.warnings.to_h { |notice| [notice.code, notice.level] }

      expect(levels).to eq("unknown_department" => "important", "unknown_department_archived" => "hint")
    end

    it "names where the credential came from" do
      sources = {"database" => "DB", "variables" => "ENV", "file" => "YAML"}
      sources.each do |source, shown|
        allow(Wsjrdp::Credentials).to receive(:lookup).and_return(double(answer: double(source: source)))
        expect(Wsjrdp::Sync::MossApi.credential_source("default")).to eq(shown)
      end
    end
  end

  describe "people and their Moss users" do
    def notice(run, code) = part(run, users_key).plan_object.warnings.find { |warning| warning.code == code }

    it "names a person under contract whose Moss e-mail is no user's as important" do
      person = people(:ul_a_1)
      person.update!(moss_email: "nicht.in.moss@example.org")
      person.update_columns(status: "confirmed", contract_status: "confirmed")

      found = notice(start, "person_without_moss_user")

      expect(found).to have_attributes(level: "important")
      expect(found.items.keys).to eq(["person:#{person.id}"])
      expect(found.items.values.first).to include("Vertrag: confirmed", "Moss-E-Mail: nicht.in.moss@example.org")
      expect(found.items.values.first).to end_with("kein Moss-Benutzer namens #{person.first_name} #{person.last_name}")
    end

    it "names the Moss users of the same name, in case the e-mail is wrong" do
      user = lists["users"].find { |record| record["firstName"].present? && record["lastName"].present? }
      person = Fabricate(:person, first_name: " #{user["firstName"].upcase}", last_name: user["lastName"],
        moss_email: "falsch@example.org")
      person.update_columns(status: "confirmed", contract_status: "confirmed")

      text = notice(start, "person_without_moss_user").items["person:#{person.id}"]

      role = person.reload.wsjrdp_role
      expect(text.include?("Rolle: #{role}")).to eq(role.present?)
      expect(text).to end_with("Moss-Benutzer gleichen Namens: #{user["email"]} (#{user["status"]})")
    end

    it "only hints at one without a contract or who left" do
      left = people(:ul_a_1)
      left.update!(moss_email: "weg@example.org")
      left.update_columns(status: "deregistered", contract_status: "ended")
      waiting = Fabricate(:person, moss_email: "wartet@example.org")
      waiting.update_columns(contract_status: "none")

      run = start

      expect(notice(run, "person_without_moss_user")).to be_nil
      expect(notice(run, "person_without_moss_user_expected")).to have_attributes(level: "hint")
      expect(notice(run, "person_without_moss_user_expected").items.keys)
        .to contain_exactly("person:#{left.id}", "person:#{waiting.id}")
    end

    it "names a Moss user whose person has no contract as important, at the person" do
      person = people(:ul_a_1)
      person.update!(moss_email: "ben.muster@example.org")
      person.update_columns(contract_status: "none")
      user = lists["users"].find { |record| record["email"] == "ben.muster@example.org" }

      found = notice(start, "moss_user_without_contract")

      expect(found).to have_attributes(level: "important")
      expect(found.items.keys).to eq([user["id"]])
      expect(Wsjrdp::Sync::MossApi::Users.notice_fields["moss_user_without_contract"]).to eq("person_id")
    end
  end

  describe "a later run" do
    before { apply(start) }

    it "ends at once when nothing changes, marking the rows seen" do
      MossUser.update_all(last_seen_at: Time.zone.parse("2026-11-20 00:00 UTC"))

      run = start

      expect(run).to have_attributes(status: "unchanged", finished_at: be_present)
      expect(run.parts.map(&:status).uniq).to eq(["unchanged"])
      expect(MossUser.where(last_seen_at: ...Time.zone.parse("2026-11-23 14:25:01 UTC"))).to be_empty
    end

    it "updates, marks removed rows and restores them when they come back" do
      lists["teams"].first["name"] = "Team Eins neu"
      lists["users"].pop
      run = start

      expect(part(run, teams_key).plan_object.changes.map { |change| [change.action, change.values] })
        .to eq([["update", {"name" => ["Team Eins", "Team Eins neu"]}]])
      apply(run)
      expect(MossTeam.find_by!(name: "Team Eins neu")).to be_present
      expect(MossUser.removed_from_moss.pluck(:email)).to eq(["ohne.team@example.org"])
      expect(run.reload.modified_rows.to_h).to include("updated" => 1, "soft_deleted" => 1)

      lists["users"] << SyncSpecHelpers::FakeMossClient.lists["users"].last
      run = start
      expect(part(run, users_key).counts).to eq("restore" => 1)
      apply(run)
      expect(MossUser.removed_from_moss).to be_empty
    end

    it "asks twice when many rows would be removed" do
      lists["users"] = []
      run = start

      expect(codes(run, users_key)).to include("many_removed")
      expect { apply(run) }.to raise_error(Wsjrdp::Sync::Apply::Refused, "warnings_not_confirmed")

      apply(run, warnings_confirmed: true)
      expect(run.reload.warnings_confirmed_by).to eq(admin)
      expect(MossUser.in_moss).to be_empty
    end
  end

  describe "the person of a user" do
    let(:person) { people(:ul_a_1) }

    it "is filled from the Moss e-mail, but never replaced" do
      person.update!(moss_email: "Ben.Muster@example.org")
      apply(start)
      expect(MossUser.find_by!(email: "ben.muster@example.org").person).to eq(person)

      Fabricate(:person, moss_email: "ANNA.beispiel@example.org") # would match, but the person stays
      MossUser.find_by!(email: "anna.beispiel@example.org").update!(person: person)
      run = start
      apply(run)

      expect(MossUser.find_by!(email: "anna.beispiel@example.org").person).to eq(person)
    end
  end

  describe "the Moss fields of a person" do
    let(:person) { people(:ul_a_1) }

    before { person.update!(moss_email: "ben.muster@example.org", moss_phone: "0123", moss_team: "alt") }

    it "takes status, team name and roles, with one version, and leaves the phone" do
      run = start
      expect(part(run, users_key).counts).to eq("create" => 4, "update" => 1)

      expect { apply(run) }.to change { PaperTrail::Version.where(item_type: "Person", item_id: person.id).count }.by(1)

      info = person.reload.additional_info
      expect(info.slice("moss_status", "moss_team", "moss_roles", "moss_phone"))
        .to eq("moss_status" => "ACTIVE", "moss_team" => "Team Eins", "moss_roles" => %w[TEAMLEAD USER], "moss_phone" => "0123")
      expect(YAML.load(PaperTrail::Version.where(item_id: person.id).last.object_changes)["moss_team"]).to eq(["alt", "Team Eins"])
      expect(part(start, users_key).counts).to eq({})
    end

    it "removes a field Moss leaves empty" do
      apply(start)
      lists["users"][1]["teamId"] = nil

      apply(start)

      expect(person.reload.additional_info).not_to have_key("moss_team")
    end
  end

  describe "writing a changed database" do
    it "stops at a stale part, keeps its new plan, and goes on when asked" do
      run = start
      MossDepartment.create!(moss_department_uuid: lists["departments"].first["id"], name: "inzwischen angelegt")

      apply(run)

      expect(run.reload.status).to eq("stopped")
      expect(part(run, Wsjrdp::Sync::MossApi::Departments.key)).to have_attributes(status: "stale",
        counts: {"create" => 1, "update" => 1})
      expect(part(run, users_key).status).to eq("planned")
      expect(part(run, Wsjrdp::Sync::MossApi::Departments.key).timings.last).to include("status" => "stale")

      apply(run)
      expect(run.reload.status).to eq("applied")
      expect(MossDepartment.pluck(:name)).to contain_exactly("Abteilung Nord", "Abteilung Süd")
    end

    it "rolls a failed part back, stops, and skips what depends on it" do
      allow_any_instance_of(Wsjrdp::Sync::MossApi::Teams).to receive(:apply).and_raise("boom")
      run = start

      apply(run)
      expect(run.reload.status).to eq("stopped")
      expect(part(run, teams_key)).to have_attributes(status: "failed", error_message: "RuntimeError: boom")
      expect(part(run, teams_key).timings.last).to include("status" => "failed", "error_message" => "RuntimeError: boom")
      expect(MossDepartment.count).to eq(2)

      apply(run)
      expect(run.reload.status).to eq("partly_applied")
      expect(part(run, users_key).status).to eq("skipped")
      expect(MossUser.count).to eq(0)
    end

    it "never writes older data over a part a newer run has written" do
      older = start(now: Time.zone.parse("2026-11-23 13:25:01 UTC"))
      lists["teams"].first["name"] = "Team Eins neu"
      apply(start)

      apply(older)

      expect(part(older, Wsjrdp::Sync::MossApi::Departments.key))
        .to have_attributes(status: "failed", error_message: I18n.t("fin.sync.run.newer_written"))
      expect(MossTeam.where(name: "Team Eins neu")).to exist
    end

    it "stops instead of hanging when something outside a part fails" do
      run = start
      allow(Wsjrdp::Sync::Files).to receive(:data).and_raise(ArgumentError, "broken")

      apply(run)

      expect(run.reload).to have_attributes(status: "stopped", error_message: "ArgumentError: broken")
    end

    it "cancels a run whose request died while writing, once it is old enough" do
      run = start
      run.update_columns(status: "applying", updated_at: 1.minute.ago)
      expect(Wsjrdp::Sync::Cancel.call(run)).to be(false)

      run.update_columns(updated_at: 11.minutes.ago)
      expect(Wsjrdp::Sync::Cancel.call(run)).to be(true)
    end

    it "touches the run after each part, so a long write never looks stuck" do
      run = start
      allow(run).to receive(:touch).and_call_original

      apply(run)

      expect(run).to have_received(:touch).exactly(3).times
    end

    it "cancels what is still to write" do
      run = start
      Wsjrdp::Sync::Cancel.call(run)

      expect(run.reload.status).to eq("cancelled")
      expect(run.parts.map(&:status).uniq).to eq(["skipped"])
    end
  end

  describe "a list Moss pages badly" do
    before { apply(start) }

    # Offset paging sorted by name: a record repeats, another is skipped.
    def answer(first, second = first, total: lists["users"].size)
      allow(client).to receive(:all).and_call_original
      allow(client).to receive(:all).with("v1/users", {sort: "name"}, page_size: 1000).and_return(first)
      allow(client).to receive(:all).with("v1/users", {sort: "-name"}, page_size: 1000).and_return(second)
      allow(client).to receive(:total_items).and_call_original
      allow(client).to receive(:total_items).with("v1/users").and_return(total)
    end

    it "fills in with a second pass in the other order" do
      users = lists["users"]
      answer([users[0], users[0], users[1], users[2]], users.reverse)

      run = start

      expect(part(run, users_key).counts).to eq({})
      expect(codes(run, users_key)).not_to include("incomplete")
    end

    it "marks nothing removed while records are still missing, and says so" do
      users = lists["users"]
      answer([users[0], users[0], users[1]], [users[1], users[1], users[0]])

      run = start

      expect(part(run, users_key).counts).to eq({})
      expect(codes(run, users_key)).to include("incomplete")
      expect(run.status).to eq("unchanged")
    end
  end

  it "fails the run when Moss does not answer, and fetches nothing after" do
    allow(client).to receive(:all).and_call_original
    allow(client).to receive(:all).with("v1/teams", {sort: "name"}, page_size: 1000).and_raise(Wsjrdp::Moss::Error, "no answer in time")

    run = start

    expect(run).to have_attributes(status: "failed", error_message: "no answer in time")
    expect(run.parts.map(&:status)).to eq(%w[skipped failed])
    expect(client).not_to have_received(:all).with("v1/users", anything)
  end

  it "deletes the files of old runs only, and notes it on their parts" do
    old = start(now: 100.days.ago)
    recent = start(now: Time.current)
    leftover = ".tmp-0123456789abcdef-#{part(old, users_key).files.first["name"]}" # an interrupted write
    File.write(Wsjrdp::Sync::Files.root.join(leftover), "{}")

    expect(Wsjrdp::Sync::Purge.call).to eq(10)

    expect(part(old, users_key).files_purged_at).to be_present
    expect(part(recent, users_key).files_purged_at).to be_nil
    expect(Dir.children(Wsjrdp::Sync::Files.root).size).to eq(9)
  end
end
