require "spec_helper"

describe PersonAbility do
  context "ist member" do
    let(:ist) { people(:ist_a_1) }

    subject { Ability.new(ist.reload) }

    context "in the same ist group" do
      let(:other_ist) { people(:ist_a_2) }

      context "on other ist member" do
        it_behaves_like "only allow actions", {allowed: []} do
          let(:other) { other_ist }
        end
      end
    end

    context "in a different ist group" do
      let(:other_ist) { people(:ist_b_1) }

      context "on ist member" do
        it_behaves_like "only allow actions", {allowed: []} do
          let(:other) { other_ist }
        end
      end
    end

    context "in normal unit" do
      let(:other_yp) { people(:yp_a_1) }
      let(:other_ul) { people(:ul_a_1) }

      context "on youth participant" do
        it_behaves_like "only allow actions", {allowed: []} do
          let(:other) { other_yp }
        end
      end

      context "on unit leader" do
        it_behaves_like "only allow actions", {allowed: []} do
          let(:other) { other_ul }
        end
      end
    end

    context "CMT" do
      let(:cmt) { people(:cmt_member1) }

      context "on CMT member" do
        it_behaves_like "only allow actions", {allowed: []} do
          let(:other) { cmt }
        end
      end
    end
  end
end
