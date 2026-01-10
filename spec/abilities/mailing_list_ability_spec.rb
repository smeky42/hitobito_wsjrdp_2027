require "spec_helper"

describe MailingListAbility do
  context "youth participant" do
    let(:yp) { people(:yp_a_1) }

    subject { Ability.new(yp.reload) }

    context "on mailing list in their unit" do
      it_behaves_like "only allow mailing list actions", {allowed: []} do
        let(:mailing_list) { mailing_lists(:unit_a_ml_all) }
      end
    end

    context "on mailing list in a different unit" do
      it_behaves_like "only allow mailing list actions", {allowed: []} do
        let(:mailing_list) { mailing_lists(:unit_b_ml_all) }
      end
    end

    context "on IST mailing list" do
      it_behaves_like "only allow mailing list actions", {allowed: []} do
        let(:mailing_list) { mailing_lists(:ist_a_ml) }
      end
    end
  end

  context "unit leader" do
    let(:ul) { people(:ul_a_1) }

    subject { Ability.new(ul.reload) }

    context "on mailing list in their unit" do
      it_behaves_like "only allow mailing list actions", {allowed: [:show, :index_subscriptions]} do
        let(:mailing_list) { mailing_lists(:unit_a_ml_all) }
      end
    end

    context "on mailing list in a different unit" do
      it_behaves_like "only allow mailing list actions", {allowed: []} do
        let(:mailing_list) { mailing_lists(:unit_b_ml_all) }
      end
    end

    context "on IST mailing list" do
      it_behaves_like "only allow mailing list actions", {allowed: []} do
        let(:mailing_list) { mailing_lists(:ist_a_ml) }
      end
    end
  end

  context "IST member" do
    let(:ist) { people(:ist_a_1) }

    subject { Ability.new(ist.reload) }

    context "on mailing list in their IST group" do
      it_behaves_like "only allow mailing list actions", {allowed: []} do
        let(:mailing_list) { mailing_lists(:ist_a_ml) }
      end
    end

    context "on mailing list in a different IST group" do
      it_behaves_like "only allow mailing list actions", {allowed: []} do
        let(:mailing_list) { mailing_lists(:ist_b_ml) }
      end
    end

    context "on mailing list in a normal unit" do
      it_behaves_like "only allow mailing list actions", {allowed: []} do
        let(:mailing_list) { mailing_lists(:unit_a_ml_all) }
      end
    end
  end
end
