require "spec_helper"

PERSON_ACTIONS = %i[
  show
  show_details
  show_full

  update
  update_email
  update_password
  update_settings

  security
  send_password_instructions
  totp_disable
  totp_reset

  create_invoice
  index_invoices
  fin_admin

  history
  log

  approve_add_request
  destroy
  impersonate_user
  index_notes
  index_tags
  manage_tags
  primary_group
]

shared_examples "only allow actions" do |params|
  params[:allowed].each do |action|
    it "can #{action}" do
      is_expected.to be_able_to(action, other)
    end
  end

  (PERSON_ACTIONS - params[:allowed]).each do |action|
    it "can not #{action}" do
      is_expected.to_not be_able_to(action, other)
    end
  end
end
