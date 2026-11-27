# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The form of the tab Anmelde-Dokumente has one CSRF token, bound to the
# form's URL: every button posts there and names its operation.
describe "Anmelde-Dokumente form token", type: :request do
  around do |example|
    protection = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    example.run
  ensure
    ActionController::Base.allow_forgery_protection = protection
  end

  let(:root) { Pathname(Dir.mktmpdir("wsjrdp-documents")) }

  before do
    allow(Wsjrdp2027::DocumentStore).to receive(:root).and_return(root)
    sign_in(Fabricate(Group::Root::Admin.name.to_sym, group: groups(:root)).person)
  end

  after { FileUtils.rm_rf(root) }

  it "is accepted for every operation of the form" do
    get "/document_management/registration_documents"
    form = Capybara.string(response.body).find("form#registration-documents-form")
    token = form.find("input[name=authenticity_token]", visible: false).value
    expect(form).to have_button(name: "operation", value: "register")

    post form[:action], params: {authenticity_token: token, operation: "register_all"}

    expect(response).to have_http_status(:redirect)
  end
end
