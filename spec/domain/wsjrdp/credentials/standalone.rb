# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Loads Wsjrdp::Credentials without Rails, for the specs of this directory.
# They are deliberately standalone (no rails spec_helper): the parts are
# plain Ruby, and the full test boot must never be pointed at a shared
# database by accident. From the wagon directory:
#
#   bundle exec rspec spec/domain/wsjrdp/credentials
#
# Not a *_spec.rb file, so rspec loads it only through require_relative.
require "logger"
# Kernel#pp loads pp on its first call; #pretty_inspect needs it loaded.
require "pp" # rubocop:disable Lint/RedundantRequireStatement
require "stringio"
require "yaml"
require "active_support"
require "active_support/json"
require "active_support/message_encryptor"

# The files declare `module Wsjrdp::Credentials` (compact style); without
# Zeitwerk the parent constant has to exist first.
module Wsjrdp; end

# The made-up, committed keys the specs need by value: the key of the
# golden-vector spec, and where the Rails environment test's key is
# (Wsjrdp::Credentials::Keys::PUBLIC_FINGERPRINTS names both).
module CredentialsSpec
  GOLDEN_VECTOR_KEY = "465416874a322c86649b40b6b7fc3297c554c8d2b008734a3761101c0355705c"
  TEST_SETTINGS = File.expand_path("../../../../config/settings/test.yml", __dir__)

  # The secrets of credentials.keys_default in config/settings/test.yml.
  def self.test_settings_secrets
    YAML.safe_load_file(TEST_SETTINGS).dig("credentials", "keys_default").to_s.split(",")
      .map { |entry| entry.split(":", 2).last.strip }
  end
end

# Needs shown (the objects to print) and secrets (texts none may show).
RSpec.shared_examples "credential hygiene" do
  it "never shows a secret, and refuses a dump" do
    shown.each do |object|
      [object.inspect, object.to_s, object.pretty_inspect, object.to_json].each do |text|
        # The message names the class only: the text would show the secret.
        secrets.each { |secret| expect(text).not_to include(secret), "#{object.class} shows a secret" }
      end
      next unless object.is_a?(Wsjrdp::Credentials::Undumpable)

      expect { Marshal.dump(object) }.to raise_error(TypeError), object.class.name
      expect { YAML.dump(object) }.to raise_error(TypeError), object.class.name
    end
  end
end

%w[instant_input credentials credentials/keys credentials/sealer credentials/field credentials/kind
  credentials/kinds credentials/credential credentials/lookup credentials/override credentials/variables
  credentials/local_file credentials/overrides].each do |file|
  require_relative "../../../../app/domain/wsjrdp/#{file}"
end
