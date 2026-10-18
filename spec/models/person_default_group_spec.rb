# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# Person#default_group: the group of the core's default_group_id, which
# /people/:id leads to.
describe Person do
  let(:ul) { people(:ul_a_1) }

  it "is the primary group" do
    expect(ul.default_group).to eq(ul.primary_group)
  end

  it "is the primary group without a role left in it" do
    Fabricate(Group::Ist::Member.name.to_sym, person: ul, group: groups(:ist_a))
    ul.roles.where(group_id: ul.primary_group_id).delete_all

    expect(ul.reload.default_group).to eq(ul.primary_group)
  end

  it "is a group with a role without a primary group" do
    ul.update_columns(primary_group_id: nil)

    expect(ul.reload.default_group).to eq(ul.groups.first)
    expect(ul.default_group).to be_present
  end

  it "is the root group without a primary group and roles" do
    person = Fabricate(:person)
    person.update_columns(primary_group_id: nil)

    expect(person.reload.default_group).to eq(Group.root)
  end

  it "is the group of default_group_id" do
    [ul, people(:admin)].each { |person| expect(person.default_group.id).to eq(person.default_group_id) }
    ul.update_columns(primary_group_id: nil)
    expect(ul.reload.default_group.id).to eq(ul.default_group_id)
  end
end
