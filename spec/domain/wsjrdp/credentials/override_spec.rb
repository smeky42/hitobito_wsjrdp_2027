# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Standalone, without Rails (see standalone.rb).
require_relative "standalone"

# The choice inside an override: a version is usable from valid_from on and
# up to, not including, expires_at, and only when its values fit the kind;
# of the usable ones the newest wins -- by created_at when every version
# states it, else by the list. The values are made up.
describe Wsjrdp::Credentials::Override do
  let(:kind) { Wsjrdp::Credentials::Kinds.load.fetch("api_key") }

  def version(position, key = "made-up-#{position}", **options)
    described_class::Version.new(position: position, values: {"base_url" => "https://api.example.org", "api_key" => key},
      **options)
  end

  def account(versions, **options)
    described_class::Account.new(kind: kind, account_key: "default", versions: versions, **options)
  end

  def chosen(account, at: Time.utc(2026, 12, 2))
    account.answer(at: at, stage: "development", source: "file").candidates.map(&:version_name)
  end

  describe "the window" do
    let(:windowed) do
      account([version(1, name: "w", valid_from: Time.utc(2027, 5, 1), expires_at: Time.utc(2027, 11, 1))])
    end

    it "counts from valid_from on, up to but not including expires_at" do
      expect(chosen(windowed, at: Time.utc(2027, 4, 30, 23, 59, 59))).to eq([])
      expect(chosen(windowed, at: Time.utc(2027, 5, 1))).to eq(["w"])
      expect(chosen(windowed, at: Time.utc(2027, 10, 31, 23, 59, 59))).to eq(["w"])
      expect(chosen(windowed, at: Time.utc(2027, 11, 1))).to eq([])
    end

    it "names the state of each version" do
      examined = ->(at) { windowed.examine(at: at, stage: "development").map(&:state) }
      expect(examined.call(Time.utc(2027, 1, 1))).to eq([:not_yet_valid])
      expect(examined.call(Time.utc(2027, 6, 1))).to eq([:active])
      expect(examined.call(Time.utc(2027, 12, 1))).to eq([:expired])
    end
  end

  describe "the order" do
    it "takes the first usable version of the list when none states created_at" do
      versions = [version(1, name: "first", expires_at: Time.utc(2026, 12, 1)), version(2, name: "second"),
        version(3, name: "third")]

      expect(chosen(account(versions))).to eq(%w[second third])
    end

    it "takes the newest by created_at when every version states it, the list deciding a tie" do
      versions = [version(1, name: "old", created_at: Time.utc(2026, 6, 18)),
        version(2, name: "new", created_at: Time.utc(2026, 11, 20)),
        version(3, name: "tie-a", created_at: Time.utc(2026, 9, 1)),
        version(4, name: "tie-b", created_at: Time.utc(2026, 9, 1))]

      expect(chosen(account(versions, order: described_class::BY_CREATED_AT))).to eq(%w[new tie-a tie-b old])
    end

    it "keeps the window to whether a version counts, never which one wins" do
      versions = [version(1, name: "successor", created_at: Time.utc(2026, 11, 1), valid_from: Time.utc(2026, 12, 1)),
        version(2, name: "current", created_at: Time.utc(2026, 11, 2))]
      ordered = account(versions, order: described_class::BY_CREATED_AT)

      expect(chosen(ordered, at: Time.utc(2026, 11, 15))).to eq(%w[current])
      expect(chosen(ordered, at: Time.utc(2026, 12, 2))).to eq(%w[current successor])
    end
  end

  describe "the values" do
    it "casts them with the kind and hands them out through the Credential" do
      credential = account([version(1, "made-up-secret", name: "v")]).answer(at: Time.now.utc, stage: "development",
        source: "file").candidates.first

      expect(credential[:base_url]).to eq("https://api.example.org")
      expect(credential.secret(:api_key)).to eq("made-up-secret")
      expect { credential[:api_key] }.to raise_error(Wsjrdp::Credentials::Credential::WrongAccess)
      expect(credential).to have_attributes(version_id: nil, version_name: "v", key_fingerprint: nil,
        stage: "development")
    end

    it "makes a version whose values do not fit the kind kind_mismatch, with the codes of the cast" do
      missing = described_class::Version.new(position: 1, values: {"base_url" => "https://api.example.org"})
      examination = account([missing, version(2)]).examine(at: Time.now.utc, stage: "development").first

      expect(examination.state).to eq(:kind_mismatch)
      expect(examination.credential).to be_nil
      expect(examination.errors.map(&:to_s)).to eq(["api_key: required"])
      expect(chosen(account([missing, version(2)]))).to eq([nil])
    end

    it "keeps the warnings of the cast" do
      plain = described_class::Version.new(position: 1, values: {"base_url" => "http://api.example.org", "api_key" => "x"})
      examination = account([plain]).examine(at: Time.now.utc, stage: "production").first

      expect(examination.state).to eq(:active)
      expect(examination.warnings.map(&:to_s)).to eq(["base_url: not_https"])
    end
  end

  describe "a refused account" do
    it "answers for the account with no usable version" do
      answer = account([version(1)], refused: true).answer(at: Time.now.utc, stage: "production", source: "variables")

      expect(answer.candidates).to eq([])
      expect(answer.states).to eq({refused: 1})
      expect(account([version(1)], refused: true).examine(at: Time.now.utc, stage: "production").first.credential)
        .to be_nil
    end
  end

  describe "hygiene" do
    let(:made) { version(1, "made-up-secret-value", name: "made-up name", created_at: Time.utc(2026, 11, 20, 9)) }
    let(:shown) { [made, account([made]), *account([made]).examine(at: Time.now.utc, stage: "test")] }
    let(:secrets) { ["made-up-secret-value", "made-up name"] }

    include_examples "credential hygiene"

    it "shows the field names and the instants of a version" do
      expect(made.inspect).to include("fields=base_url,api_key", "created_at=2026-11-20T09:00:00+00:00")
    end
  end
end
