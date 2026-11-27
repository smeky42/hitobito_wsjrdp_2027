# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027
module Wsjrdp::Sync::MossApi
  # The Moss wallets (GET /v1/bank-accounts, without paging) and their
  # balances, onto the finance accounts. A wallet finds its account by UUID,
  # else it takes the one Moss wallet account without a UUID. Anything else
  # fails this part, never the run: an account is never created or guessed.
  class BankAccounts < Wsjrdp::Sync::Part
    self.key = "moss_api.master_data.bank_accounts"
    self.source = KIND
    PATH = "v1/bank-accounts"
    DATA_NAME = "bank-accounts"
    BALANCES = "balances"
    UUID_COLUMN = "moss_bank_account_uuid"
    BALANCE_COLUMNS = %w[moss_balance moss_available_balance].freeze
    CLOSED = "CLOSED"

    # A Moss wallet that fits no account, or not just one.
    class Unmatched < Wsjrdp::Sync::PartError; end

    # {lower-case UUID => account} of the given change and notice keys.
    def self.records_for(keys)
      WsjrdpFinAccount.where(UUID_COLUMN => keys).index_by { |account| account[UUID_COLUMN].to_s.downcase }
    end

    # The balance of a closed wallet is not read; its account keeps the last one.
    def fetch(client)
      records = Array(client.get(PATH)["data"]).uniq { |record| record["id"].to_s.downcase }
      read_at = context.now.utc.iso8601
      balances = records.reject { |record| record["accountStatus"] == CLOSED }.to_h do |record|
        [record["id"], client.get("#{PATH}/#{record["id"]}/balance")["data"].merge("readAt" => read_at)]
      end
      {DATA_NAME => records, BALANCES => balances}
    end

    def plan(data)
      accounts = match(data)
      changes = accounts.filter_map { |uuid, (account, attributes)| change(uuid, account, attributes) } +
        removed(accounts).map { |account| remove(account) }
      Wsjrdp::Sync::Plan.new(changes: changes, warnings: notices(accounts, changes))
    end

    def apply(data, plan)
      accounts = match(data)
      stats = Wsjrdp::Sync::Stats.new
      plan.changes.each do |change|
        if change.action == "remove"
          stats.add("soft_deleted", WsjrdpFinAccount.where(UUID_COLUMN => change.key)
            .update_all(moss_removed_at: context.now, updated_at: context.now))
        else
          account, attributes = accounts.fetch(change.key)
          stats.add("updated", WsjrdpFinAccount.where(id: account.id)
            .update_all(attributes.merge("moss_removed_at" => nil, "updated_at" => context.now)))
        end
      end
      stats
    end

    private

    def records(data) = Array(data[DATA_NAME]).map { |record| record.merge("id" => record["id"].to_s.downcase) }

    # {uuid => [account, attributes]}; raises Unmatched.
    def match(data)
      by_uuid = WsjrdpFinAccount.where(UUID_COLUMN => records(data).pluck("id")).index_by { |account| account[UUID_COLUMN] }
      known, unknown = records(data).partition { |record| by_uuid.key?(record["id"]) }
      deleted = known.select { |record| by_uuid.fetch(record["id"]).deleted_at }
      raise Unmatched, deleted_message(deleted, by_uuid) if deleted.any?

      matched = known.to_h do |record|
        account = by_uuid.fetch(record["id"])
        [record["id"], [account, settled(account, attributes(record, data))]]
      end
      return matched if unknown.empty?

      matched.merge(link(unknown, data))
    end

    def link(unknown, data)
      candidates = WsjrdpFinAccount.moss_wallets.where(UUID_COLUMN => nil).order(:id).to_a
      record = unknown.sole if unknown.one?
      account = candidates.sole if candidates.one?
      fits = record && account && account.opening_balance_currency == record["currency"]
      raise Unmatched, unmatched_message(unknown, candidates) unless fits

      {record["id"] => [account, settled(account, attributes(record, data)).merge(UUID_COLUMN => record["id"])]}
    end

    def deleted_message(records, by_uuid)
      accounts = records.map { |record| by_uuid.fetch(record["id"]) }
      I18n.t("fin.sync.bank_accounts.deleted",
        accounts: accounts.map { |account| "#{account[UUID_COLUMN]} → #{account.id} #{account}" }.join(", "))
    end

    def unmatched_message(unknown, candidates)
      I18n.t("fin.sync.bank_accounts.unmatched",
        moss: unknown.map { |record| "#{record["id"]} (#{record["currency"]}, #{record["accountStatus"]})" }.join(", "),
        hitobito: candidates.map { |account| "#{account.id} #{account} (#{account.opening_balance_currency})" }
          .join(", ").presence || I18n.t("fin.sync.bank_accounts.none"))
    end

    def attributes(record, data)
      attributes = {"moss_organisation_uuid" => record["organisationId"], "moss_funding_type" => record["fundingType"],
                    "moss_account_status" => record["accountStatus"], "moss_currency" => record["currency"]}
      balance = balances(data)[record["id"]]
      if balance
        check_currency(record, balance)
        attributes.merge!("moss_balance" => balance.dig("balance", "amount"),
          "moss_available_balance" => balance.dig("availableBalance", "amount"),
          "moss_balance_first_seen_at" => Wsjrdp::InstantInput.parse(balance["readAt"]))
      end
      attributes.to_h { |column, value| [column, WsjrdpFinAccount.type_for_attribute(column).cast(value)] }
    end

    def check_currency(record, balance)
      currencies = [balance.dig("balance", "currency"), balance.dig("availableBalance", "currency")].compact.uniq
      return if currencies == [record["currency"]]

      raise Wsjrdp::Sync::PartError, I18n.t("fin.sync.bank_accounts.other_currency", uuid: record["id"],
        currency: record["currency"], balance: currencies.join(", "))
    end

    def balances(data) = data.fetch(BALANCES, {}).transform_keys { |uuid| uuid.to_s.downcase }

    # The balance keeps its time while its amounts stay the same.
    def settled(account, attributes)
      same = BALANCE_COLUMNS.all? { |column| account[column] == attributes.fetch(column, account[column]) }
      same ? attributes.merge("moss_balance_first_seen_at" => account.moss_balance_first_seen_at) : attributes
    end

    def change(uuid, account, attributes)
      diff = attributes.filter_map { |column, value| [column, [account[column], value]] unless account[column] == value }.to_h
      action = if account.moss_removed_at then "restore"
      elsif diff.any? then "update"
      end
      return unless action

      Wsjrdp::Sync::Plan::Change.new(action: action, key: uuid, label: account.to_s, values: diff.as_json,
        target: WsjrdpFinAccount.name)
    end

    def removed(accounts)
      WsjrdpFinAccount.in_moss.where.not(UUID_COLUMN => accounts.keys).order(:id)
    end

    def remove(account)
      Wsjrdp::Sync::Plan::Change.new(action: "remove", key: account[UUID_COLUMN], label: account.to_s, values: {},
        target: WsjrdpFinAccount.name)
    end

    def notices(accounts, changes)
      gone = changes.select { |change| change.action == "remove" }
      notices = []
      if gone.any? && gone.size == WsjrdpFinAccount.in_moss.count
        notices << warning("many_removed", gone.to_h { |change| [change.key, change.label] }, table: self.class.label)
      end
      differing = accounts.select { |_uuid, (account, attributes)| status_differs?(account, attributes) }
      if differing.any?
        notices << important("status_differs", differing.to_h { |uuid, (account, attributes)|
          [uuid, "#{account} · Hitobito #{account.status_display} · Moss #{attributes["moss_account_status"]}"]
        })
      end
      notices
    end

    def status_differs?(account, attributes) = (account.status == "active") != (attributes["moss_account_status"] == "ACTIVE")
  end
end
