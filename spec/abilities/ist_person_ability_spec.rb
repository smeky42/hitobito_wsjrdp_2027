require "spec_helper"

describe PersonAbility do
  context "ist member" do
    let(:ist) { people(:ist_a_1) }

    subject { Ability.new(ist.reload) }

    context "in the same ist group" do
      context "on other ist member" do
        it_behaves_like "only allow person actions", {allowed: []} do
          let(:other) { people(:ist_a_2) }
        end
      end

      it_behaves_like "only allow role actions", {allowed: []} do
        let(:role) { Role.new(person: people(:ul_a_1), group: groups(:ist_a)) }
      end
    end

    context "in a different ist group" do
      context "on ist member" do
        it_behaves_like "only allow person actions", {allowed: []} do
          let(:other) { people(:ist_b_1) }
        end
      end

      it_behaves_like "only allow role actions", {allowed: []} do
        let(:role) { Role.new(person: people(:ul_a_1), group: groups(:ist_b)) }
      end
    end

    context "in normal unit" do
      context "on youth participant" do
        it_behaves_like "only allow person actions", {allowed: []} do
          let(:other) { people(:yp_a_1) }
        end
      end

      context "on unit leader" do
        it_behaves_like "only allow person actions", {allowed: []} do
          let(:other) { people(:ul_a_1) }
        end
      end

      it_behaves_like "only allow role actions", {allowed: []} do
        let(:role) { Role.new(person: people(:ul_a_1), group: groups(:unit_b)) }
      end
    end

    context "CMT" do
      context "on CMT member" do
        it_behaves_like "only allow person actions", {allowed: []} do
          let(:other) { people(:cmt_member1) }
        end
      end

      it_behaves_like "only allow role actions", {allowed: []} do
        let(:role) { Role.new(person: people(:ul_a_1), group: groups(:root)) }
      end
    end
  end
end
