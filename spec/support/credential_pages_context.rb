# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The credential store pages, signed in as an admin. No response may hold a
# secret value or an encrypted text, except the answer of a reveal. Every
# value is made up.
RSpec.shared_context "credential pages" do
  let(:admin) { people(:admin).tap { |person| Group::Root::Admin.create!(person: person, group: groups(:root)) } }
  let(:kinds) { Wsjrdp::Credentials::Kinds.current }
  let(:password) { "made-up-smtp-password-4711" }
  let(:moss_secret) { "made-up-moss-secret-0815" }
  let(:mail_values) do
    {"mail_from" => "finanzen@example.org", "smtp_host" => "mail.example.org", "smtp_password" => password}
  end
  let(:mail_account) { {kind: "mail_account", account_key: "finanzen"} }
  let(:moss_account) { {kind: "moss_api", account_key: "default"} }

  before do
    use_overrides
    sign_in(admin)
  end

  def html = Capybara.string(response.body)

  # The empty template row of further fields (a parser keeps a template's
  # content apart).
  def further_template = response.body[%r{<template[^>]*credential-further-template[^>]*>.*?</template>}m].to_s

  def deposit!(kind: "mail_account", account_key: "finanzen", values: mail_values, **options)
    Wsjrdp::Credentials::Deposit.call(kind: kind, account_key: account_key, values: values, **options)
      .tap { |result| expect(result).to be_saved }.record
  end

  def moss!(**options)
    deposit!(kind: "moss_api", account_key: "default",
      values: {"client_id" => "made-up-client", "client_secret" => moss_secret}, **options)
  end

  # The variables name moss_api/default.
  def use_env_override(extra = {})
    use_overrides(variables: Wsjrdp::Credentials::Variables.new(
      {"HITOBITO_CREDENTIAL__TEST__MOSS_API__DEFAULT__CLIENT_ID" => "env-client",
       "HITOBITO_CREDENTIAL__TEST__MOSS_API__DEFAULT__CLIENT_SECRET" => "made-up-env-secret"}.merge(extra),
      stage: "test", kinds: kinds
    ))
  end

  # What the edit form carries as credential[lock].
  def lock_of(row) = row.reload.updated_at.utc.iso8601(6)

  def secret_of(row, field) = row.reload.field_values(keys: Wsjrdp::Credentials::Keys.current)[field]

  # A row with an encrypted public field, as a changed kind may leave it.
  def seal_public!(row, field, value)
    row.write_field(field, value, secret: true, key: Wsjrdp::Credentials::Keys.current.active)
    row.save!
    row
  end

  # A new active key; the committed test key is still accepted.
  def other_keys = Wsjrdp::Credentials::Keys.new("test:#{"c" * 64},#{Settings.credentials.keys_default}", stage: "test")

  def use_keys(keys) = allow(Wsjrdp::Credentials::Keys).to receive(:current).and_return(keys)

  def expect_nothing_secret(*secrets, rows: WsjrdpCredential.all)
    texts = secrets + rows.flat_map { |row| row.sealed_texts.values }
    texts.each { |text| expect(response.body).not_to include(text) }
  end
end
