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

  # Unit managers hold layer_and_below_full on their own unit layer:
  # almost everything on their unit's events, but no :log.
  context "unit manager" do
    let(:um) { people(:um_a_1) }

    subject { Ability.new(um.reload) }

    context "on event in their unit" do
      it_behaves_like "only allow event actions", {allowed: [:show, :create, :update, :destroy,
        :application_market, :qualify, :qualifications_read, :index_participations,
        :manage_tags, :manage_attachments]} do
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

  # layer_and_below_full on the IST layer must not grant :log.
  context "IST leader (MIST)" do
    let(:mist) { people(:mist_a_1) }

    subject { Ability.new(mist.reload) }

    context "on IST event in their IST group" do
      it_behaves_like "only allow event actions", {allowed: [:show, :create, :update, :destroy,
        :application_market, :qualify, :qualifications_read, :index_participations,
        :manage_tags, :manage_attachments]} do
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

  context "CMT leader" do
    let(:leader) { people(:cmt_leader) }

    subject { Ability.new(leader.reload) }

    context "on event in a unit" do
      it_behaves_like "only allow event actions", {allowed: [:show, :update,
        :index_participations, :manage_attachments, :manage_tags, :log]} do
        let(:event) { events(:event_unit_a) }
      end
    end

    context "on IST event" do
      it_behaves_like "only allow event actions", {allowed: [:show, :update,
        :index_participations, :manage_attachments, :manage_tags, :log]} do
        let(:event) { events(:event_ist_a) }
      end
    end
  end
end
