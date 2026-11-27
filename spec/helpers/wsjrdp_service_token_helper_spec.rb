# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The stored value of an API key on its pages: what it is, where it works.
describe WsjrdpServiceTokenHelper do
  let(:keys) { Wsjrdp2027::ServiceTokenHmacKeys.current }

  def shown(**attrs) = helper.format_service_token_token(ServiceToken.new(**attrs))

  def text(key, **args) = I18n.t("service_tokens.token.#{key}", **args)

  def dev_value(key)
    Wsjrdp2027::ServiceTokenHmacKeys.new("development:#{"d" * 64}", stage: "development").digests(key).first
  end

  it "shows an HMAC of this stage with its stage, the fingerprint of its secret, and that it works here" do
    value = keys.active.digest("k")
    html = shown(token: value, stage: "test", hmac_secret_key_fingerprint: keys.active.fingerprint)

    expect(html).to include(value, text(:hmac, stage: helper.service_token_stage_name("test")),
      keys.active.fingerprint, text("reach.here"))
  end

  it "marks an HMAC of another stage" do
    html = shown(token: dev_value("x"), stage: "development")

    expect(html).to include(text(:hmac, stage: helper.service_token_stage_name("development")),
      text(:fingerprint_unknown), text("reach.other_stage"))
  end

  it "shows a SHA-256 or a key itself as working everywhere, without a fingerprint" do
    sha = shown(token: ServiceToken.digest_token("k"))
    plain = shown(token: "Legacy0123456789")

    expect(sha).to include(text(:sha256))
    expect(plain).to include("Legacy0123456789", text(:plain))
    [sha, plain].each { expect(_1).not_to include(text(:fingerprint), text("reach.here")) }
  end

  it "labels a hash and a key stored as it is apart" do
    expect([ServiceToken.digest_token("k"), "Legacy"].map { helper.service_token_token_label(ServiceToken.new(token: _1)) })
      .to eq([text("label.hashed"), text("label.plain")])
  end
end
