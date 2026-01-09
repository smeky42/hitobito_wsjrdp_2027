require "spec_helper"

EVENT_ACTIONS = [
  :show,
  :application_market,
  :create,
  :destroy,
  :index_invitations,
  :index_participations,
  :manage_attachments,
  :manage_tags,
  :qualifications_read,
  :qualify,
  :update
]

describe "EVENT_ACTIONS" do
  it "has complete list of actions" do
    defined_actions = Set.new
    Ability.store.configs.values.each do |config|
      if config.subject_class == Event && config.permission != :_class_side
        defined_actions.add(config.action)
      end
    end

    expect(EVENT_ACTIONS).to match_array(defined_actions)
  end
end

shared_examples "only allow event actions" do |params|
  it "can perform allowed actions" do
    allowed_actions = EVENT_ACTIONS.select do |action|
      subject.can?(action, event)
    end
    expect(allowed_actions).to match_array(params[:allowed])
  end

  it "can not perform other actions" do
    forbidden_actions = EVENT_ACTIONS.select do |action|
      subject.cannot?(action, event)
    end
    expect(forbidden_actions).to match_array(EVENT_ACTIONS - params[:allowed])
  end
end
