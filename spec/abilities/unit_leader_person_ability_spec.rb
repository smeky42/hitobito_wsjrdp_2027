require "spec_helper"

describe PersonAbility do
  context "unit leader" do
    let(:ul) { people(:ul_a_1) }

    subject { Ability.new(ul.reload) }

    context "in the same unit" do
      let(:other_yp) { people(:yp_a_1) }
      let(:other_ul) { people(:ul_a_2) }

      context "on youth participant" do
        it_behaves_like "only allow person actions", {allowed: [:show, :show_details]} do
          let(:other) { other_yp }
        end
      end

      context "on other unit leader" do
        it_behaves_like "only allow person actions", {allowed: [:show, :show_details]} do
          let(:other) { other_ul }
        end
      end
    end

    context "in a different unit" do
      let(:other_yp) { people(:yp_b_1) }
      let(:other_ul) { people(:ul_b_1) }

      context "on youth participant" do
        it_behaves_like "only allow person actions", {allowed: []} do
          let(:other) { other_yp }
        end
      end

      context "on unit leader" do
        it_behaves_like "only allow person actions", {allowed: []} do
          let(:other) { other_ul }
        end
      end
    end

    context "CMT" do
      let(:cmt) { people(:cmt_member1) }

      context "on CMT member" do
        it_behaves_like "only allow person actions", {allowed: []} do
          let(:other) { cmt }
        end
      end
    end

    context "IST" do
      let(:ist) { people(:ist_a_1) }

      context "on IST member" do
        it_behaves_like "only allow person actions", {allowed: []} do
          let(:other) { ist }
        end
      end
    end
  end
end
