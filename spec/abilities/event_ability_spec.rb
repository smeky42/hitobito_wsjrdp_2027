require "spec_helper"

describe EventAbility do
  context "youth participant" do
    let(:yp) { people(:yp_a_1) }

    subject { Ability.new(yp.reload) }

    context "on event in their unit" do
      it_behaves_like "only allow event actions", {allowed: [:show]} do
        let(:event) { events(:event_unit_a) }
      end
    end

    context "on event in different unit" do
      it_behaves_like "only allow event actions", {allowed: []} do
        let(:event) { events(:event_unit_b) }
      end
    end

    context "on IST event" do
      it_behaves_like "only allow event actions", {allowed: []} do
        let(:event) { events(:event_ist_a) }
      end
    end
  end

  context "unit leader" do
    let(:ul) { people(:ul_a_1) }

    subject { Ability.new(ul.reload) }

    context "on event in their unit" do
      it_behaves_like "only allow event actions", {allowed: [:show, :create, :update, :destroy,
        :index_participations, :manage_attachments]} do
        let(:event) { events(:event_unit_a) }
      end
    end

    context "on event in different unit" do
      it_behaves_like "only allow event actions", {allowed: []} do
        let(:event) { events(:event_unit_b) }
      end
    end

    context "on IST event" do
      it_behaves_like "only allow event actions", {allowed: []} do
        let(:event) { events(:event_ist_a) }
      end
    end
  end

  context "IST member" do
    let(:ist) { people(:ist_a_1) }

    subject { Ability.new(ist.reload) }

    context "on IST event in their IST group" do
      it_behaves_like "only allow event actions", {allowed: [:show]} do
        let(:event) { events(:event_ist_a) }
      end
    end

    context "on IST event in different IST group" do
      it_behaves_like "only allow event actions", {allowed: []} do
        let(:event) { events(:event_ist_b) }
      end
    end

    context "on event in normal unit" do
      it_behaves_like "only allow event actions", {allowed: []} do
        let(:event) { events(:event_unit_a) }
      end
    end
  end
end
