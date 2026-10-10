# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe Wsjrdp2027::PrimaryRoleChange do
  let(:ul) { people(:ul_a_1) }
  let(:admin) { people(:admin) }
  let(:ist_group) { groups(:ist_a) }
  let(:unit_b) { groups(:unit_b) }
  let(:confirmed_at) { Time.zone.local(2025, 12, 16, 18, 0) }

  def build_change(person = ul, **attrs)
    described_class.new(person: person.reload, by: admin, **attrs)
  end

  def confirm!(person)
    person.update_columns(status: "confirmed", contract_status: "confirmed", contract_confirmed_at: confirmed_at,
      contract_confirmed_by_type: "Person", contract_confirmed_by_id: admin.id,
      payment_role: "RegularPayer::Group::Unit::Leader")
  end

  describe "to a role with another fee (UL to IST)" do
    before { confirm!(ul) }

    let(:subject_change) { build_change(group_id: ist_group.id, role_type: "Group::Ist::Member") }

    it "says what follows before anything happens" do
      expect(subject_change).to be_complete
      expect(subject_change).to be_valid
      expect(subject_change.payment_role_changes?).to be(true)
      expect(subject_change.contract_replaced?).to be(true)
      expect(subject_change.status_to_registered?).to be(true)
      expect(subject_change.notices.map { |n| [n.level, n.topic] }).to include(%i[info contract])
      expect(subject_change.old_regular_full_fee_eur).to eq(2400)
      expect(subject_change.new_regular_full_fee_eur).to eq(2600)
      expect(subject_change.end_roles).to eq([roles(:ul_a_1)])
    end

    it "moves the person, ends the contract and sets status back to registered, logged and noted" do
      with_versioning { subject_change.save! }

      ul.reload
      expect(ul.primary_group).to eq(ist_group)
      expect(ul.roles.map(&:type)).to eq(["Group::Ist::Member"])
      expect(Role.with_inactive.find(roles(:ul_a_1).id).end_on).to eq(Time.zone.yesterday)
      expect(ul).to have_attributes(status: "registered", contract_status: "replacement_pending",
        contract_confirmed_at: confirmed_at, contract_ended_at: nil, payment_role: "RegularPayer::Group::Ist::Member")
      expect(ul.notes.last.text).to eq("Am #{Time.zone.today.strftime("%d.%m.%Y")} von #{groups(:unit_a).display_name} " \
        "nach #{ist_group.display_name} verschoben. Rolle von #{Group::Unit::Leader.model_name.human} zu " \
        "#{Group::Ist::Member.model_name.human} gewechselt. Neuer Vertrag nötig: drucken, unterschreiben und hochladen. Bis zur Bestätigung gilt der bisherige Vertrag")
      expect(ul.versions.reorder(:id).last.changeset.keys).to include("contract_status", "status", "primary_group_id")
    end
  end

  describe "to a role with the same fee (Unit A to Unit B)" do
    before { confirm!(ul) }

    it "keeps contract and status" do
      c = build_change(group_id: unit_b.id, role_type: "Group::Unit::Leader")
      expect(c.payment_role_changes?).to be(false)

      c.save!

      ul.reload
      expect(ul.primary_group).to eq(unit_b)
      expect(ul).to have_attributes(status: "confirmed", contract_status: "confirmed", contract_ended_at: nil)
    end
  end

  describe "the contract chosen against the payment role type" do
    before { confirm!(ul) }

    it "keeps contract and status on another payment role type when the dialog says so" do
      c = build_change(group_id: ist_group.id, role_type: "Group::Ist::Member", contract: "keep")
      expect(c).to have_attributes(new_contract_by_default?: true, contract_replaced?: false, status_to_registered?: false,
        contract_choice_differs?: true, contract_kept_unfit?: true)
      expect(c.notices.map { |n| [n.level, n.topic] }).to eq([%i[danger contract], %i[info contract]])

      c.save!

      expect(ul.reload).to have_attributes(status: "confirmed", contract_status: "confirmed", contract_ended_at: nil)
      expect(Note.where(subject: ul).last.text).not_to include("Vertrag")
    end

    it "ends contract and status on the same payment role type when the dialog says so" do
      c = build_change(group_id: unit_b.id, role_type: "Group::Unit::Leader", contract: "end")
      expect(c).to have_attributes(new_contract_by_default?: false, contract_replaced?: true, status_to_registered?: true,
        contract_kept_unfit?: false)
      expect(c.notices.map { |n| [n.level, n.topic] }).to eq([%i[warning contract]])

      c.save!

      expect(ul.reload).to have_attributes(status: "registered", contract_status: "replacement_pending")
      expect(Note.where(subject: ul).last.text).to eq("Am #{Time.zone.today.strftime("%d.%m.%Y")} von " \
        "#{groups(:unit_a).display_name} nach #{unit_b.display_name} verschoben. Neuer Vertrag nötig: drucken, unterschreiben und hochladen. Bis zur Bestätigung gilt der bisherige Vertrag")
    end

    it "ignores the choice without a contract in force" do
      ul.update_columns(status: "printed", contract_status: "none", contract_confirmed_at: nil,
        contract_confirmed_by_type: nil, contract_confirmed_by_id: nil)
      c = build_change(group_id: ist_group.id, role_type: "Group::Ist::Member", contract: "keep")
      expect(c).to have_attributes(contract_in_force?: false, new_contract?: true, contract_replaced?: false,
        status_to_registered?: true, contract_kept_unfit?: false, contract_choice_differs?: false)
    end

    it "follows the payment role type without a choice and refuses an unknown one" do
      expect(build_change(group_id: unit_b.id, role_type: "Group::Unit::Leader")).to have_attributes(contract_replaced?: false)
      maybe = build_change(group_id: unit_b.id, role_type: "Group::Unit::Leader", contract: "maybe")
      expect(maybe).not_to be_valid
      expect(maybe.errors[:base]).to include("Unbekannte Auswahl beim Vertrag.")
    end
  end

  describe "the roles" do
    it "preselects the only role with a fee, but keeps an empty choice once the dialog showed it" do
      expect(build_change(group_id: ist_group.id, role_type: "Group::Ist::Member").end_role_ids).to eq([roles(:ul_a_1).id])
      kept = build_change(group_id: ist_group.id, role_type: "Group::Ist::Member", end_roles_chosen: "1",
        keep_role_ids: [roles(:ul_a_1).id])
      expect(kept.end_role_ids).to eq([])
    end

    it "ends the roles with a fee in the primary group the dialog did not tick to stay" do
      second = Fabricate(Group::Unit::Member.name.to_sym, person: ul, group: groups(:unit_a))
      c = build_change(group_id: ist_group.id, role_type: "Group::Ist::Member", end_roles_chosen: "1",
        keep_role_ids: [second.id.to_s])
      expect(c.end_role_ids).to eq([roles(:ul_a_1).id])
    end

    it "marks the role the fee came from" do
      expect(build_change(group_id: ist_group.id, role_type: "Group::Ist::Member").old_fee_roles).to eq([roles(:ul_a_1)])
    end

    it "leaves roles without a fee and roles in other groups as they are" do
      manager = Fabricate(Group::Unit::Manager.name.to_sym, person: ul, group: groups(:unit_a))
      elsewhere = Fabricate(Group::Root::Leader.name.to_sym, person: ul, group: groups(:root))
      c = build_change(group_id: ist_group.id, role_type: "Group::Ist::Member")

      expect(c.primary_other_roles).to eq([manager])
      expect(c.other_group_roles).to eq([elsewhere])
      c.save!

      expect(ul.reload.roles).to include(manager, elsewhere)
    end

    it "refuses roles that are not roles with a fee in the primary group" do
      c = build_change(group_id: ist_group.id, role_type: "Group::Ist::Member", end_role_ids: [roles(:yp_a_1).id])

      expect(c).not_to be_valid
      expect(c.errors[:base]).to include("Zu beendende Rollen müssen Beitragsrollen der Hauptgruppe sein.")
    end
  end

  describe "the choice" do
    it "offers only groups and role types with a fee" do
      expect(described_class.target_groups).to include(groups(:unit_a), ist_group, groups(:root))
      types = build_change(group_id: groups(:root).id).target_role_types.map(&:sti_name)
      expect(types).to contain_exactly("Group::Root::Leader", "Group::Root::Member")
    end

    it "refuses a role type the group does not have with a fee" do
      c = build_change(group_id: groups(:root).id, role_type: "Group::Root::Admin")

      expect(c).not_to be_complete
      expect(c).not_to be_valid
      expect(c.errors[:role_type]).to be_present
    end

    it "keeps the role it already is, ending nothing, when group and role stay" do
      c = build_change(group_id: groups(:unit_a).id, role_type: "Group::Unit::Leader")
      expect(c).to have_attributes(unchanged?: true, existing_target_role: roles(:ul_a_1), end_roles: [])
      expect(c).to be_valid

      expect { c.save! }.not_to(change { Role.with_inactive.count })
      expect(ul.reload.primary_group).to eq(groups(:unit_a))
      expect(Note.where(subject: ul)).to be_empty
      expect(c.note_text).to eq("Hauptgruppe und Rolle unverändert")
    end

    it "warns about a deregistration in progress, but allows the change" do
      ul.update_columns(status: "deregistration_noted")
      c = build_change(group_id: ist_group.id, role_type: "Group::Ist::Member")

      expect(c).to be_valid
      expect(c.status_notices.map { |n| [n.level, n.topic] }).to eq([%i[warning status]])
      expect(c.notices.first.text).to eq("Im Status „Abmeldung Vermerkt“ ist keine erneute Registrierung möglich.")
    end
  end

  describe "the note" do
    it "names a role change in the same group with the date" do
      c = build_change(group_id: groups(:unit_a).id, role_type: "Group::Unit::Member")
      expect(c.note_text).to start_with("Am #{Time.zone.today.strftime("%d.%m.%Y")} Rolle von " \
        "#{Group::Unit::Leader.model_name.human} zu #{Group::Unit::Member.model_name.human} gewechselt")
    end
  end

  describe "unit code and payment role" do
    before { confirm!(ul) }

    it "takes the unit code of the new unit group for a YP or UL" do
      unit_b.update!(unit_code: "B1")
      c = build_change(group_id: unit_b.id, role_type: "Group::Unit::Leader")
      expect(c).to have_attributes(new_unit_code: "B1", unit_code_changes?: true)
      expect(c.notices.map(&:topic)).not_to include(:unit)
      expect(c.note_text).not_to include("Unit-Code")

      c.save!

      expect(ul.reload.unit_code).to eq("B1")
    end

    it "sets the payment role when the contract stays, so that the fee follows" do
      c = build_change(group_id: ist_group.id, role_type: "Group::Ist::Member", contract: "keep")
      expect(c).to have_attributes(payment_role_set?: true, new_payment_role: "RegularPayer::Group::Ist::Member")
      expect(c.notices.map { |n| [n.level, n.topic] }).to include(%i[info contract])

      c.save!

      expect(ul.reload).to have_attributes(status: "confirmed", payment_role: "RegularPayer::Group::Ist::Member")
    end
  end

  describe "a role started today" do
    it "is removed instead of ended, since it cannot end before it starts" do
      today_role = Fabricate(Group::Ist::Member.name.to_sym, person: ul, group: ist_group, start_on: Time.zone.today)
      ul.update_columns(primary_group_id: ist_group.id)
      roles(:ul_a_1).destroy!(always_soft_destroy: true)
      c = build_change(group_id: groups(:unit_a).id, role_type: "Group::Unit::Leader", end_roles_chosen: "1")
      expect(c.end_roles).to eq([today_role])

      expect { c.save! }.not_to raise_error
      expect(Role.with_inactive.where(id: today_role.id)).to be_empty
      expect(ul.reload.primary_group).to eq(groups(:unit_a))
    end
  end

  describe "a role the person holds in the new primary group already" do
    it "becomes the primary role as it is" do
      leader = Fabricate(Group::Ist::Leader.name.to_sym, person: ul, group: ist_group)
      c = build_change(group_id: ist_group.id)
      expect(c.role_type).to eq("Group::Ist::Leader")
      expect(c.existing_target_role).to eq(leader)
      expect(c.role_type_chips("Group::Ist::Leader")).to include("vorhanden")

      expect { c.save! }.not_to change { Role.with_inactive.count }

      ul.reload
      expect(ul.primary_group).to eq(ist_group)
      expect(ul.roles).to eq([leader])
    end
  end

  describe "the starting point" do
    it "preselects the current primary group, without a role, and groups the targets under headings" do
      c = build_change
      expect(c.group_id).to eq(groups(:unit_a).id)
      expect(c.role_type).to be_nil
      expect(c).not_to be_complete
      headings = c.grouped_target_groups.map(&:first)
      expect(headings.first(3)).to eq(%w[CMT ISTs Units])
      chips = c.grouped_target_groups.to_h.fetch("Units").to_h
      expect(chips[groups(:unit_a)]).to include("bisher")
    end

    it "says to choose group and role before saving" do
      c = build_change(group_id: groups(:unit_a).id, role_type: "")

      expect(c).not_to be_valid
      expect(c.errors.full_messages).to include("Rolle wählen")
    end
  end

  describe "the role choice" do
    it "starts with the current role type in a group of the same kind" do
      expect(build_change(group_id: unit_b.id)).to have_attributes(role_type: "Group::Unit::Leader")
    end

    it "keeps a role emptied on purpose, but starts anew when the group changes" do
      Fabricate(Group::Ist::Leader.name.to_sym, person: ul, group: ist_group)
      expect(build_change(group_id: ist_group.id).role_type).to eq("Group::Ist::Leader")
      expect(build_change(group_id: ist_group.id, role_type: "", role_group_id: ist_group.id).role_type).to be_nil
      stale = build_change(group_id: ist_group.id, role_type: "Group::Unit::Leader", role_group_id: groups(:unit_a).id)
      expect(stale.role_type).to eq("Group::Ist::Leader")
    end

    it "names the current role and says whether the new group offers its fee" do
      expect(build_change.old_role_label).to eq("Unit Leader")
      expect(build_change(group_id: unit_b.id).old_payment_role_type_offered?).to be(true)
      expect(build_change(group_id: ist_group.id).old_payment_role_type_offered?).to be(false)
    end
  end

  describe "the WSJ role" do
    it "is chosen in the dialog, also where none was set" do
      ul.update_columns(wsj_role: "UL")
      c = build_change(group_id: ist_group.id, role_type: "Group::Ist::Member", wsj_role: "IST")
      c.save!
      expect(ul.reload.wsj_role).to eq("IST")

      other = people(:ul_a_2)
      unset = build_change(other, group_id: ist_group.id, role_type: "Group::Ist::Member")
      expect(unset).to have_attributes(suggested_wsj_role: "IST", new_wsj_role: nil)
      c = build_change(other, group_id: ist_group.id, role_type: "Group::Ist::Member", wsj_role: "CMT")
      c.save!
      expect(other.reload.wsj_role).to eq("CMT")
    end

    it "preselects unset when the stored one repeats the old payment role, and keeps one set on purpose" do
      ul.update_columns(wsj_role: "UL", payment_role: "RegularPayer::Group::Unit::Leader")
      c = build_change(group_id: ist_group.id, role_type: "Group::Ist::Member")
      expect(c).to have_attributes(chosen_wsj_role: "", new_wsj_role: nil, wsj_role_unfit?: false)

      ul.update_columns(wsj_role: "JPT")
      c = build_change(group_id: ist_group.id, role_type: "Group::Ist::Member")
      expect(c).to have_attributes(chosen_wsj_role: "JPT", new_wsj_role: "JPT", wsj_role_unfit?: true)
      expect(c.notices.map(&:topic)).to include(:wsj_role)
      expect(c.notices.find { |n| n.topic == :wsj_role }).to have_attributes(level: :warning, text: include("WSJ-Rolle JPT"))
      expect(build_change(group_id: ist_group.id, role_type: "Group::Ist::Member", wsj_role: "IST").wsj_role_unfit?).to be(false)
    end
  end
end
