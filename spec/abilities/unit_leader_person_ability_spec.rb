require "spec_helper"

describe PersonAbility do
  context "unit leader" do
    let(:ul) { people(:ul_a_1) }

    subject { Ability.new(ul.reload) }

    context "in the same unit" do
      context "on youth participant" do
        it_behaves_like "only allow person actions", {allowed: [:show, :show_details, :show_full,
          :update, :send_password_instructions]} do
          let(:other) { people(:yp_a_1) }
        end
      end

      context "on other unit leader" do
        it_behaves_like "only allow person actions", {allowed: [:show, :show_details, :show_full,
          :update, :send_password_instructions]} do
          let(:other) { people(:ul_a_2) }
        end
      end

      it_behaves_like "only allow role actions", {allowed: []} do
        let(:role) { Role.new(person: people(:yp_b_1), group: groups(:unit_a)) }
      end
    end

    context "in a different unit" do
      context "on youth participant" do
        it_behaves_like "only allow person actions", {allowed: []} do
          let(:other) { people(:yp_b_1) }
        end
      end

      context "on unit leader" do
        it_behaves_like "only allow person actions", {allowed: []} do
          let(:other) { people(:ul_b_1) }
        end
      end

      it_behaves_like "only allow role actions", {allowed: []} do
        let(:role) { Role.new(person: people(:yp_a_2), group: groups(:unit_b)) }
      end
    end

    context "CMT" do
      context "on CMT member" do
        it_behaves_like "only allow person actions", {allowed: []} do
          let(:other) { people(:cmt_member1) }
        end
      end

      it_behaves_like "only allow role actions", {allowed: []} do
        let(:role) { Role.new(person: people(:yp_a_2), group: groups(:root)) }
      end
    end

    context "IST" do
      context "on IST member" do
        it_behaves_like "only allow person actions", {allowed: []} do
          let(:other) { people(:ist_a_1) }
        end
      end

      it_behaves_like "only allow role actions", {allowed: []} do
        let(:role) { Role.new(person: people(:yp_a_2), group: groups(:ist_a)) }
      end
    end
  end
end
