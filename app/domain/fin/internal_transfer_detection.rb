# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The Umbuchungen the statements suggest, worked out fresh on every call (one
# SQL query, a few milliseconds on the contingent's data -- measured in
# doc/fin/internal_transfers.md). Nothing is stored until a user, or the import
# API, links a suggestion (WsjrdpInternalTransfer.link!).
#
# A PAIR is an outflow and an inflow of the same amount on two different own
# accounts at most WINDOW_DAYS calendar days apart, where every IBAN a side
# names belongs to the other side's account and at least one side names one.
# An account's own IBANs are its `iban` and its `top_up_iban`. That one rule
# covers transfers between the bank accounts, the interest the notice account
# passes on (only the arriving side names an IBAN) and the Moss top-ups (the
# bank side names the wallet's top-up IBAN; a Moss transaction names none).
#
# Only free rows take part: current bank transactions and Moss transactions
# that are no leg yet and that nobody marked "Keine Umbuchung"; a pair one of
# its rows denies ("keine davon") is left out (WsjrdpInternalTransferLeg).
#
#   #unique     pairs whose rows have no other candidate -- linked by "verknüpfen"
#               or automatically by the import API
#   #ambiguous  the remaining pairs, grouped: one group is all pairs that share
#               a row, so the user picks one of them
#   #missing    rows that name another own account's IBAN but have no partner:
#               "waiting" for WAITING_BANK_DAYS bank days (Wsjrdp2027::Target2)
#               after their date, "ohne Gegenseite" after that
class Fin::InternalTransferDetection
  # 3 bank days in the worst case of weekends and holidays (incl. banks
  # closed on 24 and 31 December) take up to 10 calendar days.
  WINDOW_DAYS = 10
  WAITING_BANK_DAYS = 3

  Pair = Data.define(:from, :to, :named) do
    def key = "#{from.key}>#{to.key}"

    def amount = to.amount

    def gap = (to.date - from.date).to_i

    # Which statement made the pair: the Moss top-up, both sides naming the
    # other, the outflow naming the receiver, or the inflow naming the sender.
    def rule
      return :moss_top_up if to.moss?

      {"both" => :both_ibans, "from" => :receiver_iban, "to" => :sender_iban}.fetch(named)
    end
  end

  Missing = Data.define(:leg, :named_account, :waiting_until) do
    def waiting?(today = Date.current) = today <= waiting_until
  end

  def initialize(today: Date.current)
    @today = today
  end

  def pairs
    @pairs ||= load_pairs
  end

  def unique
    @unique ||= pairs.select { |pair| pair_count(pair.from) == 1 && pair_count(pair.to) == 1 }
  end

  def ambiguous
    @ambiguous ||= components(pairs - unique)
  end

  def missing
    @missing ||= load_missing
  end

  def waiting = missing.select { |entry| entry.waiting?(@today) }

  def without_counterpart = missing.reject { |entry| entry.waiting?(@today) }

  # Anything for the user to decide (the waiting rows only inform).
  def open_count = unique.size + ambiguous.size + without_counterpart.size

  private

  def pair_count(leg)
    @pair_counts ||= pairs.flat_map { |pair| [pair.from.key, pair.to.key] }.tally
    @pair_counts.fetch(leg.key)
  end

  # Pairs sharing a row end up in one group (connected components).
  def components(list)
    groups = []
    list.each do |pair|
      touching = groups.select { |group| group.any? { |other| shares_leg?(pair, other) } }
      merged = touching.flatten + [pair]
      groups = (groups - touching) << merged
    end
    groups.map { |group| group.sort_by(&:key) }.sort_by { |group| group.first.from.date }
  end

  def shares_leg?(one, other)
    [one.from.key, one.to.key].intersect?([other.from.key, other.to.key])
  end

  def load_pairs
    rows = connection.select_rows(PAIRS_SQL)
    legs = load_legs(rows.flat_map { |a_src, a_id, b_src, b_id, _named| [[a_src, a_id], [b_src, b_id]] })
    rows.map do |a_src, a_id, b_src, b_id, named|
      Pair.new(from: legs.fetch("#{a_src}:#{a_id}"), to: legs.fetch("#{b_src}:#{b_id}"), named: named)
    end.sort_by { |pair| [pair.from.date, pair.key] }
  end

  def load_missing
    paired = pairs.flat_map { |pair| [pair.from.key, pair.to.key] }.to_set
    rows = connection.select_rows(MISSING_SQL).reject { |id, _account_id| paired.include?("camt:#{id}") }
    legs = load_legs(rows.map { |id, _account_id| ["camt", id] })
    accounts = WsjrdpFinAccount.where(id: rows.map(&:last)).index_by(&:id)
    rows.map do |id, account_id|
      leg = legs.fetch("camt:#{id}")
      Missing.new(leg: leg, named_account: accounts[account_id],
        waiting_until: waiting_until(leg.date))
    end.sort_by { |entry| [-entry.leg.date.jd, entry.leg.key] }
  end

  def waiting_until(date)
    day = date
    WAITING_BANK_DAYS.times { day = Wsjrdp2027::Target2.bank_day_after(day) }
    day
  end

  def load_legs(source_ids)
    by_source = source_ids.group_by(&:first).transform_values { |list| list.map(&:last).uniq }
    records = WsjrdpCamtTransaction.includes(:fin_account).where(id: by_source.fetch("camt", [])).to_a +
      MossTransaction.includes(:fin_account).where(id: by_source.fetch("moss", [])).to_a
    records.map { |record| Fin::InternalTransferLeg.new(record) }.index_by(&:key)
  end

  def connection = ActiveRecord::Base.connection

  OWN_IBANS_SQL = <<~SQL
    SELECT id AS account_id, iban FROM wsjrdp_fin_accounts WHERE NULLIF(iban, '') IS NOT NULL AND deleted_at IS NULL
    UNION
    SELECT id, top_up_iban FROM wsjrdp_fin_accounts WHERE NULLIF(top_up_iban, '') IS NOT NULL AND deleted_at IS NULL
  SQL

  FREE_LEGS_SQL = <<~SQL
    SELECT 'camt' AS src, c.id, c.fin_account_id AS account_id, c.signed_base_amount AS amount, c.value_date AS day,
           c.dbtr_iban, c.cdtr_iban, c.additional_info
    FROM wsjrdp_camt_transactions c
    WHERE c.deleted_at IS NULL AND c.replaced_by_id IS NULL AND c.internal_transfer_id IS NULL
      AND c.fin_account_id IS NOT NULL AND c.value_date IS NOT NULL
      AND NOT coalesce((c.additional_info ->> '#{WsjrdpInternalTransferLeg::NOT_TRANSFER_KEY}')::boolean, false)
    UNION ALL
    SELECT 'moss', t.id, t.fin_account_id, t.signed_total_base_amount, t.booking_date, NULL, NULL, t.additional_info
    FROM moss_transactions t
    WHERE t.internal_transfer_id IS NULL AND t.fin_account_id IS NOT NULL AND t.booking_date IS NOT NULL
      AND NOT coalesce((t.additional_info ->> '#{WsjrdpInternalTransferLeg::NOT_TRANSFER_KEY}')::boolean, false)
  SQL

  DENYLIST = WsjrdpInternalTransferLeg::DENYLIST_KEY

  PAIRS_SQL = <<~SQL
    WITH own AS (#{OWN_IBANS_SQL}), legs AS (#{FREE_LEGS_SQL})
    SELECT a.src, a.id, b.src, b.id,
           CASE WHEN oa.iban IS NOT NULL AND ob.iban IS NOT NULL THEN 'both'
                WHEN oa.iban IS NOT NULL THEN 'from' ELSE 'to' END AS named
    FROM legs a
    JOIN legs b ON b.amount = -a.amount AND b.account_id <> a.account_id
               AND b.day BETWEEN a.day - #{WINDOW_DAYS} AND a.day + #{WINDOW_DAYS}
    LEFT JOIN own oa ON oa.account_id = b.account_id AND oa.iban = a.cdtr_iban
    LEFT JOIN own ob ON ob.account_id = a.account_id AND ob.iban = b.dbtr_iban
    WHERE a.amount < 0
      AND (a.cdtr_iban IS NULL OR oa.iban IS NOT NULL)
      AND (b.dbtr_iban IS NULL OR ob.iban IS NOT NULL)
      AND (oa.iban IS NOT NULL OR ob.iban IS NOT NULL)
      AND NOT coalesce(a.additional_info -> '#{DENYLIST}', '[]') ? (b.src || ':' || b.id)
      AND NOT coalesce(b.additional_info -> '#{DENYLIST}', '[]') ? (a.src || ':' || a.id)
  SQL

  # Free bank transactions naming ANOTHER own account's IBAN as their
  # counterparty: an outflow its receiver, an inflow its sender. The account
  # named comes along; the caller drops the rows that do have a pair.
  MISSING_SQL = <<~SQL
    WITH own AS (#{OWN_IBANS_SQL}), legs AS (#{FREE_LEGS_SQL})
    SELECT l.id, o.account_id
    FROM legs l
    JOIN own o ON o.account_id <> l.account_id
              AND o.iban = CASE WHEN l.amount < 0 THEN l.cdtr_iban ELSE l.dbtr_iban END
    WHERE l.src = 'camt'
  SQL
end
