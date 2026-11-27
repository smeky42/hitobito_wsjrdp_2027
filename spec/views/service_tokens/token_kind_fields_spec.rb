# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# How the key of a new API key is stored; the fields belong to the core's form
# by their form attribute.
describe "service_tokens/_token_kind_fields" do
  def page_for(token)
    without_partial_double_verification { allow(view).to receive(:entry).and_return(token) }
    render partial: "service_tokens/token_kind_fields"
    Capybara.string(rendered)
  end

  def new_token(**attrs) = ServiceToken.new(layer: groups(:root), name: "Skript", permission: "layer_read", **attrs)

  it "chooses the HMAC of this stage, and leaves the fields of an adopted hash off" do
    page = page_for(new_token)

    expect(page).to have_css("input[name='service_token[token_kind]'][form='new_service_token']", count: 4)
    expect(page).to have_css("input#service_token_token_kind_hmac[checked]")
    expect(page).to have_css("label[for=service_token_token_kind_hmac] code", text: "test")
    expect(page).to have_css("code", text: Wsjrdp2027::ServiceTokenHmacKeys.current.active.fingerprint)
    %w[adopted_token adopted_stage adopted_fingerprint].each do |field|
      expect(page).to have_css("input#service_token_#{field}[form='new_service_token'][disabled]:not([required])")
    end
    expect(page).to have_css("label[for=service_token_adopted_token] [data-required-mark][hidden]", visible: false)
  end

  it "shows a refused adopted hash again, chosen and required, with the reasons" do
    token = new_token(token_kind: "adopt", adopted_stage: "development", adopted_token: "nonsense")
    token.validate
    page = page_for(token)

    expect(page).to have_css("input#service_token_token_kind_adopt[checked]")
    expect(page).to have_css("input#service_token_adopted_token[value='nonsense'][required]:not([disabled]).is-invalid")
    expect(page).to have_css("input#service_token_adopted_stage[value='development'][required]:not([disabled])")
    expect(page).to have_css("label[for=service_token_adopted_token] [data-required-mark]:not([hidden])")
    expect(page).to have_css(".text-danger.small")
  end
end
