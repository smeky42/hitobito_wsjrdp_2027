# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027
module Wsjrdp::Sync
  # The parts that read the Moss API, and the client they read with.
  module MossApi
    KIND = "moss_api"

    # The moss_api accounts of the credential store with a usable version.
    def self.account_keys
      Wsjrdp::Credentials::Overview.new.accounts.select { |account| account.kind.to_s == KIND }
        .map(&:account_key).select { |key| usable?(key) }
    end

    def self.usable?(account_key)
      credential(account_key)
      true
    rescue Wsjrdp::Credentials::Error
      false
    end

    # Where a credential comes from, as a run keeps it.
    CREDENTIAL_SOURCES = {
      Wsjrdp::Credentials::DatabaseSource::NAME => "DB",
      Wsjrdp::Credentials::Variables::SOURCE => "ENV",
      Wsjrdp::Credentials::LocalFile::NAME => "YAML"
    }.freeze

    # The account's newest usable version.
    def self.credential(account_key) = Wsjrdp::Credentials.fetch(KIND, account_key)

    # DB, ENV or YAML: the source that answers for the account.
    def self.credential_source(account_key)
      CREDENTIAL_SOURCES[Wsjrdp::Credentials.lookup.answer(KIND, account_key).source]
    end

    def self.client(credential)
      Wsjrdp::Moss::Client.new(base_url: credential[:base_url], client_id: credential[:client_id],
        client_secret: credential.secret(:client_secret), scope: credential[:scope])
    end
  end
end
