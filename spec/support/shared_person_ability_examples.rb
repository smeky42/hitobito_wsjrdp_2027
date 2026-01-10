require "spec_helper"

PERSON_ACTIONS = [
  :show,
  :show_details,
  :show_full,

  :update,
  :update_email,
  :update_password,
  :update_settings,

  :security,
  :send_password_instructions,
  :totp_disable,
  :totp_reset,

  :create_invoice,
  :index_invoices,
  :fin_admin,

  :history,
  :log,

  :approve_add_request,
  :create,
  :destroy,
  :impersonate_user,
  :index_notes,
  :index_tags,
  :manage_tags,
  :primary_group
]

describe "PERSON_ACTIONS" do
  it "has complete list of actions" do
    defined_actions = Set.new
    Ability.store.configs.values.each do |config|
      if config.subject_class == Person && config.permission != :_class_side
        defined_actions.add(config.action)
      end
    end

    expect(PERSON_ACTIONS).to match_array(defined_actions)
  end
end

shared_examples "only allow person actions" do |params|
  it "can perform allowed actions" do
    allowed_actions = PERSON_ACTIONS.select do |action|
      subject.can?(action, other)
    end
    expect(allowed_actions).to match_array(params[:allowed])
  end

  it "can not perform other actions" do
    forbidden_actions = PERSON_ACTIONS.select do |action|
      subject.cannot?(action, other)
    end
    expect(forbidden_actions).to match_array(PERSON_ACTIONS - params[:allowed])
  end
end
