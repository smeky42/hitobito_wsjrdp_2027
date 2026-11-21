# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# NEVER REPAIR THIS SPEC BY MAKING NEW TEXTS.
#
# The texts below were sealed once (activesupport 7.1.5.1) and committed.
# They stand for every credential stored in a database. If this spec fails
# after a Rails upgrade, credentials sealed before it can no longer be
# opened: stop the upgrade and find out what changed in
# ActiveSupport::MessageEncryptor (doc/wsjrdp/credentials.md, "Sealing").
# Replacing the texts would only hide that.
#
# Rails 7.1 writes the inner envelope in one of two spellings and reads
# both: the legacy one, {"_rails":{"message":"<Base64 of the JSON>",...}},
# when ActiveSupport::Messages::Metadata.use_message_serializer_for_metadata
# is off (as it is without the app), and {"_rails":{"data":{...},...}} when it
# is on (as `load_defaults 7.1` sets it in the app). There is one text of
# each.
#
# The key and the values are made up. Standalone, without Rails (see
# standalone.rb).
require_relative "standalone"

describe "Wsjrdp::Credentials::Sealer golden vectors" do
  let(:key) do
    Wsjrdp::Credentials::Keys.new("test:#{CredentialsSpec::GOLDEN_VECTOR_KEY}", stage: "test").active
  end
  let(:account) { {stage: "test", kind: "mail_account", account_key: "finanzen"} }
  let(:fields) do
    {"mail_from" => "finanzen@example.org", "smtp_host" => "mail.example.org", "smtp_port" => 587,
     "smtp_password" => "made-up-pässword", "imap_port" => 993}
  end

  # Sealed with use_message_serializer_for_metadata off: {"_rails":{"message":...}}.
  legacy = "H7cDi8oq8mYK2Nbh8Sa4vJpDSiv2PO1aCTpnV5tnXdJcNyywR9ObVBZuDK71h1mjAnpUvWbwlCqdiJGC0NHQc1JUNxt8/G6lllraQ2" \
    "LtVxtve8nxqE66O7t6eU9d87qsyyzJshFXNsqphjbaZ7dAimx+qrfPMKj03l8h3pDpVuakYEad++GCj90LSyJAB0THGQJ/M1QTTt6Q3H" \
    "OG1kuL3FhUqsswaSZTKT/fRdDp8dUbtNrGujRTrTYshaLhcCMTH05eN5mSUbeSrBFMj2UC5303EN2UVIogUQoAMGvzhJu2PQbHZ3hGhy" \
    "rsoLvhMrXaa6XnHAr+7FShFYOrYudoKnSTkNF76A==--1NHPjRTdkUDybEP3--kykVaGmsiPevu7xlLJ0rtA=="

  # Sealed with use_message_serializer_for_metadata on: {"_rails":{"data":...}}.
  data = "bkV7m4eqrEQnSKqfcOcuGVF3wlofJP98bATMEZ7i1WbMf2T/c4BAzLMIseGpyw9+V1guHM2NYFN31zNeg8B+jIahWvhODYjPsDkkRR" \
    "NBoU/yU5sd4yxIHMd96QDmsrcN5teBA2rBTJa7fGQL9fwEHL2XcBqPIvpNL3CUlxthhT/QMyQilMQRGEFX1aFN0dYnOnFWGPBmb/9lUT" \
    "nto3u58ZR43NSbLZypggp8YW5GtoopB24WjUGXhRPYLfhaXDDGRAHeQ2cBIeJ6--m1AXHtZeMIJp0hdq--RL+BgIwXDoWzAAo53FuPIw=="

  {"legacy envelope" => legacy, "data envelope" => data}.each do |spelling, text|
    describe "the text in the #{spelling}" do
      def unseal(text, **purpose) = Wsjrdp::Credentials::Sealer.unseal(text, key: key, **account, **purpose)

      it "opens to the expected fields" do
        expect(unseal(text)).to eq(fields)
      end

      it "does not open for another purpose" do
        expect(unseal(text, account_key: "default")).to be_nil
        expect(unseal(text, stage: "development")).to be_nil
      end

      it "does not open with a changed character" do
        changed = text.dup
        changed[10] = (changed[10] == "A") ? "B" : "A"
        expect(unseal(changed)).to be_nil
      end
    end
  end
end
