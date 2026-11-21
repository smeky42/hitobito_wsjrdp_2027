# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Standalone, without Rails (see standalone.rb).
require_relative "standalone"

# The lookup asks its sources in order; the first that names an account
# decides for it as a whole. The sources here are made up; the database
# source is covered in spec/domain/wsjrdp/credentials_store_spec.rb. The
# values are made up.
describe Wsjrdp::Credentials::Lookup do
  let(:kind) { Wsjrdp::Credentials::Kinds.load.fetch("api_key") }
  let(:fingerprint) { Wsjrdp::Credentials::Keys.fingerprint_of("1" * 64) }

  def credential(value, id)
    Wsjrdp::Credentials::Credential.new(kind: kind, account_key: "default", stage: "test",
      values: {"base_url" => "https://api.example.org", "api_key" => value}, key_fingerprint: fingerprint,
      version_id: id)
  end

  # A source naming the accounts of answers (a Hash of [kind, account key]
  # to [candidates, states]) and recording what it was asked.
  def source(name, answers)
    Class.new do
      attr_reader :asked

      define_method(:initialize) { @asked = [] }
      define_method(:answer) do |kind, account_key|
        @asked << [kind, account_key]
        candidates, states = answers[[kind, account_key]]
        candidates && Wsjrdp::Credentials::Lookup::Answer.new(source: name, stage: "test", candidates: candidates,
          states: states)
      end
    end.new
  end

  let(:newer) { credential("made-up-newer", 2) }
  let(:older) { credential("made-up-older", 1) }
  let(:database) { source("database", {%w[api_key default] => [[newer, older], {active: 2}]}) }

  it "gives the candidates of the first source naming the account, and fetch the first of them" do
    lookup = described_class.new([source("env", {}), database])

    expect(lookup.candidates(:api_key, "default")).to eq([newer, older])
    expect(lookup.fetch("api_key", :default)).to equal(newer)
  end

  it "lets a source in front decide for the account as a whole" do
    front = source("env", {%w[api_key default] => [[], {kind_mismatch: 1}]})
    lookup = described_class.new([front, database])

    expect(lookup.candidates(:api_key, "default")).to eq([])
    expect(database.asked).to eq([])
    expect { lookup.fetch(:api_key, "default") }.to raise_error(Wsjrdp::Credentials::NoCredentialError,
      "api_key/default: no usable version in stage test (env: 1 version, none usable: kind_mismatch 1)")
  end

  it "names the states of what was found, never a value" do
    lookup = described_class.new([source("database",
      {%w[api_key default] => [[], {expired: 2, other_stage: 1}]})])

    expect { lookup.fetch(:api_key, "default") }.to raise_error(Wsjrdp::Credentials::NoCredentialError,
      "api_key/default: no usable version in stage test (database: 3 versions, none usable: expired 2, other_stage 1)")
  end

  it "says when a source has no version, and when no source names the account" do
    empty = described_class.new([source("database", {%w[api_key default] => [[], {}]})])
    expect { empty.fetch(:api_key, "default") }
      .to raise_error(Wsjrdp::Credentials::NoCredentialError, /\(database: no version\)/)

    expect { described_class.new([]).fetch(:api_key, "default") }
      .to raise_error(Wsjrdp::Credentials::NoCredentialError, "api_key/default: no usable version " \
        "(no source names the account)")
  end

  it "refuses a kind or an account key that is no name, without repeating it" do
    lookup = described_class.new([database])

    expect { lookup.fetch(:api_key, "a" * 65) }.to raise_error(ArgumentError) { |error|
      expect(error.message).not_to include("a" * 49)
    }
    expect { lookup.fetch(:api_key, "made-up secret") }.to raise_error(ArgumentError) { |error|
      expect(error.message).not_to include("made-up")
    }
    expect { lookup.candidates("Api-Key", "default") }.to raise_error(ArgumentError, /the kind is not/)
  end

  it "shows the sources, never a value, in inspect" do
    expect(described_class.new([database]).inspect).not_to include("made-up")
  end
end
