# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The token column holds an HMAC, a SHA-256 or the token itself
# (Wsjrdp2027::ServiceToken); the token is known only to the object that made
# it. HMAC token hashes work only in their stage and where their secret is
# accepted.
describe ServiceToken do
  let(:layer) { groups(:root) }
  let(:hmac_keys) { Wsjrdp2027::ServiceTokenHmacKeys }

  def make_token(name = "Skript", **attrs)
    ServiceToken.create!(layer: layer, name: name, people: true, permission: "layer_read", **attrs)
  end

  # The keys of another configuration for the block's duration.
  def with_keys(raw, stage:)
    keys = hmac_keys.new(raw, stage: stage, public_secrets: [])
    allow(hmac_keys).to receive(:current).and_return(keys)
    yield keys
  end

  def fingerprint(secret) = Base64.strict_encode64(Digest::SHA256.digest(secret))

  def dev_value(token)
    hmac_keys.new("development:#{"d" * 64}", stage: "development").digests(token).first
  end

  # API keys exist only in the root group (Wsjrdp2027::ServiceTokenAbility).
  describe "layer" do
    it "is the root group" do
      expect(ServiceToken.new(layer: groups(:root), name: "X", permission: "layer_read")).to be_valid
    end

    it "is refused anywhere else" do
      [groups(:unit_a), groups(:ist_a), Group::Root.create!(name: "CMT Warteliste", parent: groups(:root))].each do |group|
        token = ServiceToken.new(layer: group, name: "X", permission: "layer_read")
        expect(token).not_to be_valid, group.name
        expect(token.errors.full_messages).to include("Ebene muss die oberste Gruppe sein: API-Keys gibt es nur dort.")
      end
    end

    it "is refused when an API key moves out of the root group" do
      token = make_token
      token.layer = groups(:unit_a)
      expect(token).not_to be_valid
      expect(token.errors.of_kind?(:layer, :not_root)).to be(true)
    end

    it "lets an API key of another layer save its last access" do
      token = make_token
      token.update_column(:layer_group_id, groups(:unit_a).id)
      expect(token.reload.update(last_access: Time.zone.now)).to be(true)
    end
  end

  describe "making a token" do
    it "stores the HMAC with the active secret by default, with the stage and the secret's fingerprint" do
      token = make_token
      keys = hmac_keys.current
      expect(token.plain_token).to match(/\A[A-Za-z0-9_-]{50}\z/)
      expect(token.token).to eq(keys.active.digest(token.plain_token))
      expect(token.token).to match(/\Ahmac-sha256:\h{64}\z/)
      expect(token.stage).to eq("test")
      expect(token.hmac_secret_key_fingerprint).to eq(keys.active.fingerprint)
      expect(token.token_reach).to eq(:here)
    end

    it "uses the first of two secrets" do
      with_keys("test:#{"1" * 64},test:#{"2" * 64}", stage: "test") do
        expect(make_token(token_kind: "hmac").hmac_secret_key_fingerprint).to eq(fingerprint("1" * 64))
      end
    end

    it "stores the SHA-256 for sha256, bound to no stage" do
      token = make_token(token_kind: "sha256")
      expect(token.token).to eq(ServiceToken.digest_token(token.plain_token))
      expect([token.stage, token.hmac_secret_key_fingerprint]).to eq([nil, nil])
    end

    it "stores the token itself for plain" do
      token = make_token(token_kind: "plain")
      expect(token.token).to eq(token.plain_token)
    end

    it "stores an adopted token hash of another stage, with no token to show and no fingerprint" do
      value = dev_value("x" * 50)
      token = make_token(token_kind: "adopt", adopted_stage: " development ", adopted_token: " #{value.upcase} ")

      expect(token.token).to eq(value)
      expect(token.stage).to eq("development")
      expect(token.hmac_secret_key_fingerprint).to be_nil
      expect(token.plain_token).to be_nil
      expect(token.token_reach).to eq(:other_stage)
    end

    it "refuses an unknown kind" do
      token = ServiceToken.new(layer: layer, name: "X", token_kind: "rot13")
      expect(token).not_to be_valid
      expect(token.errors[:token_kind]).to be_present
    end

    it "refuses an HMAC token without an active secret, naming the reason" do
      with_keys(nil, stage: "production") do
        token = ServiceToken.new(layer: layer, name: "X")
        expect(token).not_to be_valid
        expect(token.errors[:token]).to be_empty
        expect(token.errors[:base].join).to include("HMAC-Schlüssel")
      end
    end

    it "still makes sha256 and plain tokens without an active secret" do
      with_keys(nil, stage: "production") do
        expect(make_token("A", token_kind: "sha256").token).to start_with("sha256:")
        expect(make_token("B", token_kind: "plain").plain_token).to be_present
      end
    end

    it "never makes a token with a colon" do
      allow(Devise).to receive(:friendly_token).and_return("with:colon" + "a" * 40, "b" * 50)
      expect(make_token.plain_token).to eq("b" * 50)
    end

    it "forgets the token on an object read from the database" do
      expect(ServiceToken.find(make_token.id).plain_token).to be_nil
    end
  end

  describe "adopting a token hash" do
    def adopting(stage, value) = ServiceToken.new(layer: layer, name: "X", token_kind: "adopt",
      adopted_stage: stage, adopted_token: value)

    it "needs a stage of a-z and 0-9" do
      ["", "Dev", "dev-1"].each do |stage|
        token = adopting(stage, dev_value("k"))
        expect(token).not_to be_valid, stage
        expect(token.errors[:adopted_stage]).to be_present, stage
      end
    end

    it "refuses production and this stage" do
      expect(adopting("production", dev_value("k")).tap(&:valid?).errors[:adopted_stage].join).to include("production")
      expect(adopting("test", dev_value("k")).tap(&:valid?).errors[:adopted_stage].join).to include("diese Umgebung")
    end

    it "needs an HMAC token hash" do
      ["x" * 50, ServiceToken.digest_token("k"), "hmac-sha256:abc", "hmac-sha256:development:#{"a" * 64}"].each do |value|
        token = adopting("development", value)
        expect(token).not_to be_valid, value
        expect(token.errors[:adopted_token].join).to include("hmac-sha256:"), value
      end
    end

    it "stores a given fingerprint of the secret" do
      token = adopting("development", dev_value("k"))
      token.adopted_fingerprint = " #{fingerprint("d" * 64)} "
      token.save!
      expect(token.hmac_secret_key_fingerprint).to eq(fingerprint("d" * 64))
    end

    it "needs a given fingerprint to be 44 characters of Base64" do
      ["abc", fingerprint("d" * 64).delete("="), "#{"!" * 43}="].each do |value|
        token = adopting("development", dev_value("k")).tap { |made| made.adopted_fingerprint = value }
        expect(token).not_to be_valid, value
        expect(token.errors[:adopted_fingerprint]).to be_present, value
      end
    end
  end

  describe ".find_by_plain_token" do
    let(:legacy_key) { "Legacy0123456789abcdefghijklmnopqrstuvwxyzABCDEFGH" }

    it "finds an API key in each of the three forms" do
      hmac = make_token("H")
      sha = make_token("S", token_kind: "sha256")
      plain = make_token("P", token_kind: "plain")
      legacy = make_token("L").tap { |token| token.update_columns(token: legacy_key, stage: nil) }

      expect(ServiceToken.find_by_plain_token(hmac.plain_token)).to eq(hmac)
      expect(ServiceToken.find_by_plain_token(sha.plain_token)).to eq(sha)
      expect(ServiceToken.find_by_plain_token(plain.plain_token)).to eq(plain)
      expect(ServiceToken.find_by_plain_token(legacy_key)).to eq(legacy)
    end

    it "finds nothing by a stored value" do
      hmac = make_token("H")
      sha = make_token("S", token_kind: "sha256")
      expect(ServiceToken.find_by_plain_token(hmac.token)).to be_nil
      expect(ServiceToken.find_by_plain_token(sha.token)).to be_nil
    end

    it "finds nothing for a blank, non-string or unknown token" do
      make_token
      [nil, "", ["x"], "x" * 50].each { |value| expect(ServiceToken.find_by_plain_token(value)).to be_nil }
    end

    it "finds an HMAC token by any accepted secret, and not after its secret is gone" do
      old = "development:#{"1" * 64}"
      new = "development:#{"2" * 64}"
      token = with_keys(old, stage: "development") { make_token }

      with_keys("#{new},#{old}", stage: "development") do
        expect(ServiceToken.find_by_plain_token(token.plain_token)).to eq(token)
        expect(token.token_reach).to eq(:here)
      end
      with_keys(new, stage: "development") do
        expect(ServiceToken.find_by_plain_token(token.plain_token)).to be_nil
        expect(token.token_reach).to eq(:key_missing)
      end
    end

    it "does not find a token of another stage, even with the same secret" do
      token = with_keys("development:#{"1" * 64}", stage: "development") { make_token }

      with_keys("integration:#{"1" * 64}", stage: "integration") do
        expect(ServiceToken.find_by_plain_token(token.plain_token)).to be_nil
        expect(token.token_reach).to eq(:other_stage)
      end
    end

    it "fills in the fingerprint of an adopted token hash at its first use" do
      plain = "y" * 50
      token = with_keys("development:#{"1" * 64}", stage: "development") do |keys|
        make_token.tap do |made|
          made.update_columns(token: keys.digests(plain).first, stage: "development", hmac_secret_key_fingerprint: nil)
        end
      end

      with_keys("development:#{"1" * 64}", stage: "development") do
        expect(token.reload.token_reach).to eq(:key_unknown)
        expect(ServiceToken.find_by_plain_token(plain)).to eq(token)
        expect(token.reload.hmac_secret_key_fingerprint).to eq(fingerprint("1" * 64))
        expect(token.token_reach).to eq(:here)
      end
    end

    it "does not find an HMAC token whose stored fingerprint names another secret" do
      plain = "z" * 50
      with_keys("development:#{"1" * 64}", stage: "development") do |keys|
        make_token.update_columns(token: keys.digests(plain).first, stage: "development",
          hmac_secret_key_fingerprint: fingerprint("2" * 64))
        expect(ServiceToken.find_by_plain_token(plain)).to be_nil
      end
    end

    it "finds the unhashed and sha256 forms in every stage" do
      sha = make_token("S", token_kind: "sha256")
      plain = make_token("P", token_kind: "plain")

      with_keys(nil, stage: "production") do
        expect(ServiceToken.find_by_plain_token(sha.plain_token)).to eq(sha)
        expect(ServiceToken.find_by_plain_token(plain.plain_token)).to eq(plain)
        expect(sha.token_reach).to eq(:everywhere)
      end
    end
  end

  describe "additional_info" do
    it "may be empty, and is {} by default" do
      token = make_token
      expect(token.additional_info).to eq({})
      expect(token).to be_valid
    end

    it "becomes {} when set to nil" do
      token = make_token
      token.update!(additional_info: nil)
      expect(token.reload.additional_info).to eq({})
    end

    it "keeps what is stored" do
      token = make_token
      token.update!(additional_info: {"purpose" => "Abmeldung"})
      expect(token.reload.additional_info).to eq({"purpose" => "Abmeldung"})
    end

    it "is still NOT NULL in the database" do
      column = ServiceToken.columns_hash["additional_info"]
      expect(column.null).to be(false)
    end
  end

  describe "scopes" do
    let(:admin) do
      people(:admin).tap { |person| Group::Root::Admin.create!(person: person, group: groups(:root)) }
    end

    it "follow the core columns set by the core's form" do
      token = make_token(groups: true, invoices: true)
      expect(token.scopes).to eq(%w[people groups invoices])

      token.update!(groups: false, mailing_lists: true)
      expect(token.reload.scopes).to eq(%w[people invoices mailing_lists])
    end

    it "set the core columns where only they are set, as a script does" do
      token = ServiceToken.create!(layer: layer, name: "Skript", permission: "layer_read", scopes: %w[groups events])
      expect([token.people, token.groups, token.events]).to eq([false, true, true])

      token.update!(scopes: %w[people])
      expect([token.reload.people, token.groups, token.events]).to eq([true, false, false])
    end

    it "keep the core areas from the columns when the form sends the other scopes" do
      token = make_token(acting_person: admin)
      token.update!(groups: true, wagon_scopes: %w[finance:read])
      expect(token.reload.scopes).to eq(%w[people groups finance:read])

      token.update!(wagon_scopes: [])
      expect(token.reload.scopes).to eq(%w[people groups])
    end

    it "add an extra's base with it" do
      token = ServiceToken.create!(layer: layer, name: "Skript", permission: "layer_read",
        scopes: %w[events:log finance:manage], acting_person: admin)
      expect(token.scopes).to eq(%w[events events:log finance:read finance:manage])
      expect(token.events).to be(true)
    end

    it "keep the catalogue's order and refuse unknown scopes" do
      token = make_token
      token.scopes = %w[finance:read people nonsense]
      expect(token).not_to be_valid
      expect(token.errors[:scopes].join).to include("nonsense")
    end

    it "work as extras only with an acting person" do
      token = ServiceToken.create!(layer: layer, name: "Skript", permission: "layer_read",
        scopes: %w[people people:log finance:read finance:audit])
      expect(token.effective_scopes).to eq(%w[people finance:read])
      expect(token.log_scope?(:people)).to be(false)
      expect(token.finance_permissions).to eq([:finance_read])

      token.update!(acting_person: admin)
      expect(token.effective_scopes).to eq(%w[people people:log finance:read finance:audit])
      expect(token.log_scope?(:people)).to be(true)
      expect(token.finance_permissions).to eq([:finance_read, :finance_audit])
      expect(token.finance_cap).to eq(:finance_audit)
    end

    it "give the substitute person the permissions of the effective finance scopes" do
      token = make_token(acting_person: admin, scopes: %w[people finance:read finance:write])
      expect(token.dynamic_user.roles.first.permissions).to eq([:layer_read, :finance_read, :finance])
    end

    it "have their finance part changed only by an admin" do
      token = make_token
      token.acting_person_assigner = people(:ul_a_1)
      token.wagon_scopes = %w[finance:read]
      expect(token).not_to be_valid
      expect(token.errors[:scopes].join).to include("nur ein Admin")

      token.acting_person_assigner = admin
      expect(token).to be_valid
    end
  end

  describe "acting person" do
    let(:token) { make_token }

    def assign(person, by:)
      token.acting_person_assigner = by
      token.acting_person_id = person&.id
      token.valid?
    end

    let(:admin) do
      people(:admin).tap { |person| Group::Root::Admin.create!(person: person, group: groups(:root)) }
    end

    it "may be anyone, the admin included, when an admin sets it" do
      expect(assign(people(:yp_a_1), by: admin)).to be(true)
      expect(assign(admin, by: admin)).to be(true)
      expect(assign(nil, by: admin)).to be(true)
    end

    it "is neither set nor changed nor cleared by anyone else" do
      expect(assign(people(:ul_a_1), by: people(:ul_a_1))).to be(false)
      expect(token.errors[:acting_person_id].join).to include("nur ein Admin")

      token.update_columns(acting_person_id: people(:yp_a_1).id)
      expect(assign(nil, by: people(:ul_a_1))).to be(false)
    end

    it "may be anyone outside a request" do
      expect(assign(people(:yp_a_1), by: nil)).to be(true)
    end

    it "must exist" do
      token.acting_person_id = Person.maximum(:id).to_i + 1
      expect(token).not_to be_valid
      expect(token.errors[:acting_person_id].join).to include("gibt es nicht")
    end

    it "is let go when the person is deleted" do
      person = people(:yp_a_1)
      token.update_columns(acting_person_id: person.id)
      ActiveRecord::Base.connection.execute("DELETE FROM roles WHERE person_id = #{person.id}")
      person.delete
      expect(token.reload.acting_person_id).to be_nil
    end
  end

  describe "#regenerate_token!" do
    it "offers per form the kinds a new token may have" do
      expect(make_token("H").regenerate_kinds).to eq(%w[hmac])
      expect(make_token("S", token_kind: "sha256").regenerate_kinds).to eq(%w[sha256 hmac])
      expect(make_token("P", token_kind: "plain").regenerate_kinds).to eq(%w[plain sha256 hmac])
      expect(make_token("A", token_kind: "adopt", adopted_stage: "development", adopted_token: dev_value("z" * 50))
        .regenerate_kinds).to eq([])
    end

    it "gives an HMAC token a new HMAC token; the old one finds nothing" do
      token = make_token
      old_token = token.plain_token
      token.regenerate_token!

      expect(token.token).to match(/\Ahmac-sha256:\h{64}\z/)
      expect(ServiceToken.find_by_plain_token(old_token)).to be_nil
      expect(ServiceToken.find_by_plain_token(token.plain_token)).to eq(token)
    end

    it "binds an HMAC token of a removed secret to the active one" do
      token = with_keys("development:#{"1" * 64}", stage: "development") { make_token }
      with_keys("development:#{"2" * 64}", stage: "development") do
        token.regenerate_token!
        expect(token.hmac_secret_key_fingerprint).to eq(fingerprint("2" * 64))
      end
    end

    it "turns a plain token into a plain, a sha256 or an HMAC one" do
      token = make_token(token_kind: "plain")
      token.regenerate_token!("plain")
      expect(token.token).to eq(token.plain_token)

      token.regenerate_token!("sha256")
      expect(token.token).to eq(ServiceToken.digest_token(token.plain_token))
      expect(token.stage).to be_nil

      token.regenerate_token!("hmac")
      expect(token.token).to eq(hmac_keys.current.active.digest(token.plain_token))
      expect(token.stage).to eq("test")
    end

    it "offers no HMAC token to a plain one without an active secret" do
      token = make_token(token_kind: "plain")
      with_keys(nil, stage: "production") do
        expect(token.regenerate_kinds).to eq(%w[plain sha256])
        expect { token.regenerate_token!("hmac") }.to raise_error(ActiveRecord::RecordInvalid)
      end
    end

    it "refuses a kind the API key may not get" do
      sha = make_token("S", token_kind: "sha256")
      expect { sha.regenerate_token!("plain") }.to raise_error(ActiveRecord::RecordInvalid)
      expect { make_token("H").regenerate_token!("sha256") }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "refuses a new token for an API key of another stage" do
      token = make_token(token_kind: "adopt", adopted_stage: "development", adopted_token: dev_value("z" * 50))
      expect { token.regenerate_token! }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end
end
