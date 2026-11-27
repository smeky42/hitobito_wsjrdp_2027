# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The lines of "Rechte" on an API key's pages.
describe ServiceTokenDecorator, :draper_with_helpers do
  let(:admin) { people(:admin) }

  def token(name = "Skript", **attrs)
    ServiceToken.create!(layer: groups(:root), name: name, people: true, permission: "layer_read", **attrs)
  end

  def lines(service_token)
    service_token.decorate.abilities.split(%r{<br\s*/?>}).map { |line| Nokogiri::HTML.fragment(line).text.squish }
  end

  def rights(service_token) = lines(service_token).grep_v(/\AScopes:/)

  def area(kind, action) = "#{ServiceToken.human_attribute_name(kind)} #{I18n.t("service_tokens.abilities.#{action}")}"

  def permission(name) = ServiceToken.human_attribute_name(name)

  def roles(action) = "#{Role.model_name.human(count: 2)} #{I18n.t("service_tokens.abilities.#{action}")}"

  it "shows a read-only Zugriffsbereich, reading for every kind but invoices, and no roles without groups" do
    expect(rights(token(groups: true, invoices: true))).to eq([permission(:layer_read),
      area(:people, :read), area(:groups, :read), area(:invoices, :read_write), roles(:read)])
    expect(rights(token("Nur Personen"))).to eq([permission(:layer_read), area(:people, :read)])
  end

  it "shows writing where a Zugriffsbereich with Schreibrechte grants it" do
    expect(rights(token(permission: "layer_and_below_full", groups: true, events: true)))
      .to eq([permission(:layer_and_below_full), area(:people, :read_write), area(:events, :read),
        area(:groups, :read), roles(:read_write)])
  end

  it "names the acting person, adds Log to the areas with their :log scope, and names the scopes" do
    lines = lines(token(permission: "layer_and_below_full", groups: true, events: true, invoices: true,
      acting_person: admin, wagon_scopes: %w[people:log events:log]))

    expect(lines).to eq([permission(:layer_and_below_full),
      I18n.t("service_tokens.abilities.acting_person", person: admin.to_s, id: admin.id),
      area(:people, :read_write_log), area(:events, :read_log), area(:groups, :read),
      area(:invoices, :read_write), roles(:read_write),
      I18n.t("service_tokens.abilities.scopes", scopes: "people, people:log, groups, events, events:log, invoices")])
  end

  it "names the documents of people and the highest finance scope" do
    lines = lines(token(acting_person: admin, wagon_scopes: %w[people:documents finance:read finance:audit]))

    expect(lines).to include(I18n.t("service_tokens.abilities.documents"),
      "#{I18n.t("service_tokens.abilities.finance")} #{I18n.t("wsjrdp.finance_tiers.finance_audit")}")
  end
end
