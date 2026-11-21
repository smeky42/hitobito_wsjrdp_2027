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
# The texts were replaced once, on 2026-11-21, before any credential had
# been stored anywhere: the store moved from one sealed text for all fields
# of a version to one sealed text per secret field, {"value" => ...}, with
# the field's name in the purpose.
#
# Rails 7.1 writes the inner envelope in one of two spellings and reads
# both: the legacy one, {"_rails":{"message":"<Base64 of the JSON>",...}},
# when ActiveSupport::Messages::Metadata.use_message_serializer_for_metadata
# is off (as it is without the app), and {"_rails":{"data":{...},...}} when it
# is on (as `load_defaults 7.1` sets it in the app). There are texts of
# each, for a string, an integer and true.
#
# The key and the values are made up. Standalone, without Rails (see
# standalone.rb).
require_relative "standalone"

describe "Wsjrdp::Credentials::Sealer golden vectors" do
  let(:key) do
    Wsjrdp::Credentials::Keys.new("test:#{CredentialsSpec::GOLDEN_VECTOR_KEY}", stage: "test").active
  end
  let(:account) { {stage: "test", kind: "mail_account", account_key: "finanzen"} }

  values = {"smtp_password" => "made-up-pässword", "imap_port" => 993, "made_up_flag" => true}

  # Sealed with use_message_serializer_for_metadata off: {"_rails":{"message":...}}.
  legacy = {
    "smtp_password" => "1LMOKuz0kTIoffQrKs9BwrSVHOvADn5O7sj+qDsAnWussoGOkg1xATrdsZyfVbP2tRocZGLS//btVkGeQLjUkwPCOLG0" \
      "3vmj4pgkQxXNFuYOynxY8HzyG9k1dl1c6hqzTtetJ35tBStMZOj70BZT4FbxU3JoxVDCiNg9YUx0jSmjs86UrrLZNQ==--Rx+nc+BCpXPp" \
      "VDRG--4LDgNsGdD9U8pASAIMoWnA==",
    "imap_port" => "lwrHMM1fV64LRaSmlvKEP7ZB3tqQnwoFSiTaZ7wk+G37EiLkKI7Z6QZEZ/01Y4qUYbxk5hXKBH1vCkqEux4wnIaHfUvvOFCw" \
      "YP+tjrfrB13irM7Mzy1fEM+8GVuXldgXQVLBW6YpIVFE8q+75OxNGA==--1+LUDdpJk6klUrvb--MBRiNdOTbO48NgBT31EHSQ==",
    "made_up_flag" => "m+5RFi6HEVjOuI1Q4nePi/Sx35EoUqYeqYRue4wBpFMp8EqebH3cI5uVpEgj+kSIAkaxXSWQXA5g5iD0bYc3KA0eH3b7" \
      "WYQlqMpbEWow+EUhETmo2Ff4M7om0iS1DgtEPRVrlFFIsUuFAgrQaknMsrErQg==--uw8RlB3rL2Z0/t/U--dmHQ/i6Pseid51UUfhlnKQ=="
  }

  # Sealed with use_message_serializer_for_metadata on: {"_rails":{"data":...}}.
  data = {
    "smtp_password" => "F/7T6NZ8wmqSw0BZ0P9mFUDylAimsdsGjobbeR9KCz/Pt/vHwI+gzqxUE3of9E3ufvkcl8ImACTLBMyzgN8I5vDYE8xr" \
      "UBRrkD9hL46X6sqi/x2nKz8mOcWm21cnXVCmvQzIxWmU6M8bLkNEww==--vrf8d3WROz6vgwHe--aOjc2smUdBJJ5TaM4PMUbg==",
    "imap_port" => "PIo63xV/i75nD83R2NV9X2ue2ZyVO5IpbUikJG6u6bnqw9uFl7xuErhUIlFPFQAVFHUjT4NRaCJ4GJ0f+dp2kuDtytbcDZOj" \
      "FvElcVb5vYKc0S6k1Du8viM=--qE1JMpHzOm5wIZ/i--gNj8Cc4nPwfTEJaNvVkQOQ==",
    "made_up_flag" => "fwODnJ+B/pP683JEEskNagW6FkyMWu7h50xGDzkKg/3i1JN5KVE1OwqHZcfx0vcg37GI6UvS76QBT9Ga6YnLY9NiofT7" \
      "IeTconhQKB/xgZBMlNl5WyKo6R/aQoI7--DnaZqkWn1qicF/u+--WmOLSwU147oPIL4yu+nL/w=="
  }

  {"legacy envelope" => legacy, "data envelope" => data}.each do |spelling, texts|
    describe "the texts in the #{spelling}" do
      def unseal(text, field, **purpose) = Wsjrdp::Credentials::Sealer.unseal(text, key: key, **account, field: field,
        **purpose)

      texts.each do |field, text|
        describe field do
          it "opens to the expected value" do
            expect(unseal(text, field)).to eq(values.fetch(field))
          end

          it "does not open for another purpose" do
            expect(unseal(text, field, account_key: "default")).to be_nil
            expect(unseal(text, field, stage: "development")).to be_nil
            expect(unseal(text, (field == "imap_port") ? "smtp_port" : "imap_port")).to be_nil
          end

          it "does not open with a changed character" do
            changed = text.dup
            changed[10] = (changed[10] == "A") ? "B" : "A"
            expect(unseal(changed, field)).to be_nil
          end
        end
      end
    end
  end
end
