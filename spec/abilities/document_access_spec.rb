# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# Who may read (:show), write (:create, :update) and hide (:destroy) a
# document (Wsjrdp2027::DocumentAccess through Wsjrdp2027::Ability).
describe Wsjrdp2027::DocumentAccess do
  let(:person) { people(:yp_a_1) }
  let(:extern) { Group::Extern.create!(name: "Extern", parent: groups(:root)) }

  def document(**attrs)
    WsjrdpDocument.new(subject: person, key: "medical", filename: "a.pdf", byte_size: 1,
      relative_storage_file_path: "x", absolute_storage_file_path: "x", **attrs)
  end

  def ability(viewer) = Ability.new(viewer)

  def role(type, group = groups(:root)) = Fabricate(type.name.to_sym, group: group).person

  it "lets only who may :log the subject read by default, and nobody but admins write or hide" do
    doc = document

    expect(ability(person)).not_to be_able_to(:show, doc)
    expect(ability(person)).not_to be_able_to(:create, doc)

    leader = people(:cmt_leader)
    expect(ability(leader)).to be_able_to(:show, doc)
    expect(ability(leader)).not_to be_able_to(:update, doc)
    expect(ability(leader)).not_to be_able_to(:destroy, doc)

    admin = role(Group::Root::Admin)
    expect(ability(admin)).to be_able_to(:update, doc)
    expect(ability(admin)).to be_able_to(:destroy, doc)
  end

  it "lets the person and who may :log them read and write where the lists say so" do
    doc = document(readable_by: %w[person log], writable_by: %w[person log], deletable_by: %w[log])

    expect(ability(person)).to be_able_to(:show, doc)
    expect(ability(person)).to be_able_to(:update, doc)
    expect(ability(person)).to be_able_to(:create, doc)
    expect(ability(person)).not_to be_able_to(:destroy, doc)
    expect(ability(people(:cmt_leader))).to be_able_to(:destroy, doc)
    expect(ability(people(:yp_a_2))).not_to be_able_to(:show, doc)
  end

  it "knows the update entry" do
    doc = document(readable_by: %w[update])

    expect(ability(people(:cmt_leader))).to be_able_to(:show, doc)
    expect(ability(person)).to be_able_to(:show, doc)
    expect(ability(people(:yp_a_2))).not_to be_able_to(:show, doc)
  end

  it "takes a finance entry as the lowest tier that reads" do
    doc = document(readable_by: %w[finance_audit])

    expect(ability(role(Group::Root::FinanceReader))).not_to be_able_to(:show, doc)
    expect(ability(role(Group::Extern::FinanceAuditor, extern))).to be_able_to(:show, doc)
    expect(ability(role(Group::Root::Finance))).to be_able_to(:show, doc)
    expect(ability(person)).not_to be_able_to(:show, doc)
  end

  it "applies the finance tier in force in the session" do
    doc = document(readable_by: %w[finance])
    finance = role(Group::Root::Finance)

    expect(Ability.new(finance, max_finance_permission: :finance)).to be_able_to(:show, doc)
    expect(Ability.new(finance, max_finance_permission: :finance_read)).not_to be_able_to(:show, doc)
  end

  it "gives nothing for an empty list or an unknown entry" do
    expect(ability(person)).not_to be_able_to(:show, document(readable_by: []))
    expect(ability(person)).not_to be_able_to(:show, document(readable_by: %w[everybody]))
  end

  it "shows documents that are not current to listed readers who may :log the subject, changes them only by admins" do
    admin = role(Group::Root::Admin)
    leader = people(:cmt_leader)

    %w[superseded deleted].each do |status|
      doc = document(status: status)

      expect(ability(person)).not_to be_able_to(:show, doc)
      expect(ability(leader)).to be_able_to(:show, doc)
      expect(ability(leader)).not_to be_able_to(:update, doc)
      expect(ability(leader)).not_to be_able_to(:destroy, doc)
      expect(ability(admin)).to be_able_to(:show, doc)
      expect(ability(admin)).to be_able_to(:destroy, doc)
    end
  end

  it "shows documents that are not current only to who is listed" do
    doc = document(status: "superseded", readable_by: %w[person])

    expect(ability(people(:cmt_leader))).not_to be_able_to(:show, doc)
  end

  it "shows documents that are not current without a subject only to admins" do
    doc = document(status: "superseded", subject: nil, readable_by: %w[person log update])

    expect(ability(people(:cmt_leader))).not_to be_able_to(:show, doc)
    expect(ability(role(Group::Root::Admin))).to be_able_to(:show, doc)
  end

  it "lets admins do everything, whatever the lists say" do
    admin = role(Group::Root::Admin)

    expect(ability(admin)).to be_able_to(:show, document(readable_by: []))
    expect(ability(admin)).to be_able_to(:update, document(writable_by: []))
  end

  it "gives nothing for a subject of a kind not in the register" do
    doc = document(subject: groups(:root), readable_by: %w[person log update finance])

    expect(ability(people(:cmt_leader))).not_to be_able_to(:show, doc)
    expect(ability(role(Group::Root::Finance))).not_to be_able_to(:show, doc)
  end
end
