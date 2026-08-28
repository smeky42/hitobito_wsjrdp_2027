require "spec_helper"

# Assignment of "admin-only" roles (Group::Root::Admin and
# Group::Root::Finance, marked via Role.admin_only_assignment): only CMT
# admins may create or update them, and only admins may take them away from
# ANOTHER person (removing one's own role is not restricted by the wagon
# rule; removing one's own permission-GIVING role stays blocked by the core
# rule general(:destroy).not_permission_giving). Ordinary roles stay
# manageable by everyone with the usual layer/group permissions.
describe RoleAbility do
  let(:root) { groups(:root) }
  let(:admin_role) { Fabricate(Group::Root::Admin.name.to_sym, group: root) }
  let(:finance_role) { Fabricate(Group::Root::Finance.name.to_sym, group: root) }

  def new_role(type, person: people(:cmt_member1))
    type.new(group: root, person: person)
  end

  subject(:ability) { Ability.new(person.reload) }

  context "as Group::Root::Leader" do
    let(:person) { people(:cmt_leader) }

    it "may not create admin-only roles" do
      expect(ability).not_to be_able_to(:create, new_role(Group::Root::Admin))
      expect(ability).not_to be_able_to(:create, new_role(Group::Root::Finance))
    end

    it "may not update another person's admin-only role" do
      expect(ability).not_to be_able_to(:update, admin_role)
      expect(ability).not_to be_able_to(:update, finance_role)
    end

    it "may not take away another person's admin-only role" do
      expect(ability).not_to be_able_to(:destroy, admin_role)
      expect(ability).not_to be_able_to(:destroy, finance_role)
      expect(ability).not_to be_able_to(:terminate, admin_role)
    end

    it "may still manage ordinary roles" do
      expect(ability).to be_able_to(:create, new_role(Group::Root::Member))
      member_role = Fabricate(Group::Root::Member.name.to_sym, group: root)
      expect(ability).to be_able_to(:update, member_role)
      expect(ability).to be_able_to(:destroy, member_role)
    end

    it "still may not create roles in an archived group (core condition kept)" do
      groups(:unit_b).update_column(:archived_at, 1.day.ago)
      role = Group::Unit::Member.new(group: groups(:unit_b).reload, person: people(:cmt_member1))
      expect(ability).not_to be_able_to(:create, role)
    end
  end

  context "as Group::Root::Finance" do
    let(:own_role) { Fabricate(Group::Root::Finance.name.to_sym, group: root) }
    let(:person) { own_role.person }

    it "may not create admin-only roles" do
      expect(ability).not_to be_able_to(:create, new_role(Group::Root::Finance))
      expect(ability).not_to be_able_to(:create, new_role(Group::Root::Admin))
    end

    it "may not take away another person's admin-only role" do
      expect(ability).not_to be_able_to(:destroy, admin_role)
      expect(ability).not_to be_able_to(:destroy, finance_role)
    end

    it "may terminate their own role (wagon rule does not restrict it)" do
      expect(ability).to be_able_to(:terminate, own_role)
    end

    it "may not destroy their own role (core lock-out protection)" do
      expect(ability).not_to be_able_to(:destroy, own_role)
    end
  end

  context "as Group::Root::Admin" do
    let(:own_role) { Fabricate(Group::Root::Admin.name.to_sym, group: root) }
    let(:person) { own_role.person }

    it "may create admin-only roles" do
      expect(ability).to be_able_to(:create, new_role(Group::Root::Admin))
      expect(ability).to be_able_to(:create, new_role(Group::Root::Finance))
    end

    it "may update and take away another person's admin-only role" do
      expect(ability).to be_able_to(:update, admin_role)
      expect(ability).to be_able_to(:destroy, admin_role)
      expect(ability).to be_able_to(:destroy, finance_role)
    end

    it "may not destroy their own admin role (core lock-out protection)" do
      expect(ability).not_to be_able_to(:destroy, own_role)
    end
  end
end
