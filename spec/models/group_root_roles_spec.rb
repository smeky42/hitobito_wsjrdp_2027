# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The roles of the contingent's leadership: Head of Contingent (HoC) holds what
# Leader, Finance and Member hold together, Extended Head of Contingent (eHoC)
# what Finance Reader, Contingent Reader and Member hold; both are assigned by
# admins only.
describe Group::Root do
  it "gives the Head of Contingent the permissions of Leader, Finance, Contingent Reader and Member" do
    expected = Group::Root::Leader.permissions | Group::Root::Finance.permissions |
      Group::Root::ContingentReader.permissions | Group::Root::Member.permissions

    expect(Group::Root::HeadOfContingent.permissions).to match_array(expected)
  end

  it "gives the Extended Head of Contingent the permissions of Finance Reader, Contingent Reader and Member" do
    expect(Group::Root::ExtendedHeadOfContingent.permissions).to match_array(
      Group::Root::FinanceReader.permissions | Group::Root::ContingentReader.permissions | Group::Root::Member.permissions
    )
  end

  it "lists each permission once" do
    [Group::Root::HeadOfContingent, Group::Root::ExtendedHeadOfContingent].each do |role|
      expect(role.permissions).to eq(role.permissions.uniq)
    end
  end

  it "gives the Contingent Reader the contingent pages only, without a fee" do
    expect(Group::Root::ContingentReader.permissions).to eq([:contingent_read])
    expect(Group::Root::ContingentReader.admin_only_assignment).to be(true)
    expect(Person::WSJRDP_ROLE_TYPE_TO_PAYMENT_ROLE_TYPE_MAP).not_to have_key("Group::Root::ContingentReader")

    reader = Fabricate(Group::Root::ContingentReader.name.to_sym, group: groups(:root)).person
    expect(Ability.new(reader.reload)).to be_able_to(:show_wsjrdp_contingent, Group.root)
  end

  it "assigns both by admins only" do
    expect([Group::Root::HeadOfContingent, Group::Root::ExtendedHeadOfContingent].map(&:admin_only_assignment))
      .to eq([true, true])
  end
end
