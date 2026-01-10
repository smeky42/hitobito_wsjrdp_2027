require "spec_helper"

MAILING_LIST_ACTIONS = [
  :_all,
  :create,
  :destroy,
  :export_subscriptions,
  :index_subscriptions,
  :show,
  :update
]

describe "MAILING_LIST_ACTIONS" do
  it "has complete list of actions" do
    defined_actions = Set.new
    Ability.store.configs.values.each do |config|
      if config.subject_class == MailingList && config.permission != :_class_side
        defined_actions.add(config.action)
      end
    end

    expect(MAILING_LIST_ACTIONS).to match_array(defined_actions)
  end
end

shared_examples "only allow mailing list actions" do |params|
  it "can perform allowed actions" do
    allowed_actions = MAILING_LIST_ACTIONS.select do |action|
      subject.can?(action, mailing_list)
    end
    expect(allowed_actions).to match_array(params[:allowed])
  end

  it "can not perform other actions" do
    forbidden_actions = MAILING_LIST_ACTIONS.select do |action|
      subject.cannot?(action, mailing_list)
    end
    expect(forbidden_actions).to match_array(MAILING_LIST_ACTIONS - params[:allowed])
  end
end
