# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe CredentialsHelper do
  describe "#credential_account_key_warnings" do
    let(:token_warning) { I18n.t("#{CredentialsHelper::I18N}.new.warnings.token") }

    def token?(key) = helper.credential_account_key_warnings(key).include?(token_warning)

    it "names as a token a long hex run, a UUID and a long run mixing letters and digits, not an ordinary name" do
      aggregate_failures do
        ["a" * 8 + "0123456789abcdef0123456789abcdef", "550e8400-e29b-41d4-a716-446655440000",
          "mk_live_ZR8q4T2nB7xW1vY9pL3s", "foo@abcdef1234567890xyzw.de"].each do |key|
          expect(token?(key)).to be(true), key
        end
        ["finanzen", "default", "foo@worldscoutjamboree.de", "vorname.nachname+test@example.org", "kasse2027",
          "mail_account_2027_finanzen", "müller"].each do |key|
          expect(token?(key)).to be(false), key
        end
      end
    end
  end
end
