require "spec_helper"

describe PersonAbility do
  context "unit leader" do
    let(:ul) { people(:ul_a_1) }

    subject { Ability.new(ul.reload) }

    context "in the same unit" do
      let(:other_yp) { people(:yp_a_1) }
      let(:other_ul) { people(:ul_a_2) }

      context "on youth participant" do
        it_behaves_like "only allow actions", {allowed: [:show]} do
          let(:other) { other_yp }
        end
      end

      context "on other unit leader" do
        it_behaves_like "only allow actions", {allowed: [:show]} do
          let(:other) { other_ul }
        end
      end
    end
  end
end
