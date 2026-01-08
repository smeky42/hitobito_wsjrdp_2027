require "spec_helper"

describe GroupAbility do
  context "youth participant" do
    let(:yp) { people(:yp_a_1) }

    subject { Ability.new(yp.reload) }

    context "on their own unit" do
      it_behaves_like "only allow group actions", {allowed: [:read]} do
        let(:group) { groups(:unit_a) }
      end
    end

    context "on other unit" do
      it_behaves_like "only allow group actions", {allowed: [:read]} do
        let(:group) { groups(:unit_b) }
      end
    end

    context "on contingent" do
      it_behaves_like "only allow group actions", {allowed: [:read]} do
        let(:group) { groups(:root) }
      end
    end

    context "on IST group" do
      it_behaves_like "only allow group actions", {allowed: [:read]} do
        let(:group) { groups(:ist_a) }
      end
    end
  end

  context "unit leader" do
    let(:ul) { people(:ul_a_1) }

    subject { Ability.new(ul.reload) }

    context "on their own unit" do
      it_behaves_like "only allow group actions", {allowed: [:read, :show_details, :index_people, :index_local_people]} do
        let(:group) { groups(:unit_a) }
      end
    end

    context "on other unit" do
      it_behaves_like "only allow group actions", {allowed: [:read]} do
        let(:group) { groups(:unit_b) }
      end
    end

    context "on contingent" do
      it_behaves_like "only allow group actions", {allowed: [:read]} do
        let(:group) { groups(:root) }
      end
    end

    context "on IST group" do
      it_behaves_like "only allow group actions", {allowed: [:read]} do
        let(:group) { groups(:ist_a) }
      end
    end
  end

  context "IST member" do
    let(:ist) { people(:ist_a_1) }

    subject { Ability.new(ist.reload) }

    context "on their own IST group" do
      it_behaves_like "only allow group actions", {allowed: [:read]} do
        let(:group) { groups(:ist_a) }
      end
    end

    context "on other IST group" do
      it_behaves_like "only allow group actions", {allowed: [:read]} do
        let(:group) { groups(:ist_b) }
      end
    end

    context "on unit" do
      it_behaves_like "only allow group actions", {allowed: [:read]} do
        let(:group) { groups(:unit_a) }
      end
    end

    context "on contingent" do
      it_behaves_like "only allow group actions", {allowed: [:read]} do
        let(:group) { groups(:root) }
      end
    end
  end
end
