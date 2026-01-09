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
    params[:allowed].each do |action|
      is_expected.to be_able_to(action, other)
    end
  end

  it "can not perform other actions" do
    (PERSON_ACTIONS - params[:allowed]).each do |action|
      is_expected.to_not be_able_to(action, other)
    end
  end
end
