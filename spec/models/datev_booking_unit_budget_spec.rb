# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027
#
#  All account numbers, names and booking texts below are invented.

require "spec_helper"

# Whether a booking belongs to a unit's budget: the booking's own flag, else its
# primary cost center, else its two accounts combined with AND, else `true` --
# and the SOURCE that travels with the value. The rule is written ONCE
# (DatevBooking's SQL constants) and read by the SELECT, the WHERE and the ORDER
# BY; `.with_unit_budget` and `DatevBooking#unit_budget` are its two entry points
# and have to agree, which is what the matrix below asserts of both at once.
describe DatevBooking do
  # A Sachkonto that says yes / no, a Kreditor that says no, and one number that
  # names no account at all (the unknown side).
  let!(:yes_account) { WsjrdpLedgerAccount.create!(number: "1200", name: "Testbank") }
  let!(:no_account) do
    WsjrdpLedgerAccount.create!(number: "66500", name: "Testaufwand", is_unit_budget: false)
  end
  let!(:no_creditor) do
    WsjrdpPersonalAccount.create!(number: "700013", name: "Testkreditor",
      account_kind: "CREDITOR", is_unit_budget: false)
  end

  # A cost center that IS a unit's own, one that is NOT, and one whose flag was
  # never answered. "K9" below names no cost center at all. Only the second one
  # decides anything; the other three leave the question to the accounts.
  let!(:unit_cost_center) do
    WsjrdpCostCenter.create!(number: "U1", name: "Unit U1", is_unit_cost_center: true)
  end
  let!(:central_cost_center) do
    WsjrdpCostCenter.create!(number: "Z1", name: "Zentral Z1", is_unit_cost_center: false)
  end
  let!(:unanswered_cost_center) do
    WsjrdpCostCenter.create!(number: "N1", name: "Ungeklärt N1", is_unit_cost_center: nil)
  end

  def booking(konto: "1200", gegenkonto: "1200", is_unit_budget: nil, **attrs)
    described_class.create!({buchungs_guid: SecureRandom.uuid,
                             booking_date: Date.new(2026, 1, 15),
                             base_amount: 10, transaction_amount: 10, debit_credit: "D",
                             account_number: konto, account_kind: "BANK",
                             offsetting_account_number: gegenkonto,
                             offsetting_account_kind: "BANK",
                             is_unit_budget: is_unit_budget}.merge(attrs))
  end

  # What the RELATION says about one booking: [effective_is_unit_budget, source].
  def from_sql(record)
    row = described_class.with_unit_budget.find(record.id)
    [row.effective_is_unit_budget, row.is_unit_budget_source]
  end

  # THE matrix: booking flag x Konto x Gegenkonto. Both entry points are asserted
  # for every cell, so the SQL and the Ruby rule can never drift apart. "99999"
  # is the UNKNOWN side -- five digits, so it is in neither master-data table and
  # no Personenkonto number either.
  describe "the rule" do
    {
      "the booking's own true beats two accounts saying no" =>
        [{is_unit_budget: true, konto: "66500", gegenkonto: "66500"}, [true, "booking"]],
      "the booking's own false beats two accounts saying yes" =>
        [{is_unit_budget: false, konto: "1200", gegenkonto: "1200"}, [false, "booking"]],
      "both accounts say yes" =>
        [{konto: "1200", gegenkonto: "1200"}, [true, "konten"]],
      "both accounts say no" =>
        [{konto: "66500", gegenkonto: "66500"}, [false, "konten"]],
      "the Konto alone says no" =>
        [{konto: "66500", gegenkonto: "1200"}, [false, "konto"]],
      "the Gegenkonto alone says no" =>
        [{konto: "1200", gegenkonto: "66500"}, [false, "gegenkonto"]],
      "an unknown Gegenkonto leaves the Konto to decide" =>
        [{konto: "1200", gegenkonto: "99999"}, [true, "konto"]],
      "an unknown Konto leaves the Gegenkonto to decide" =>
        [{konto: "99999", gegenkonto: "66500"}, [false, "gegenkonto"]],
      "neither number names an account" =>
        [{konto: "99999", gegenkonto: "99999"}, [true, "default"]],
      "an unknown Konto and a Gegenkonto saying yes" =>
        [{konto: "99999", gegenkonto: "1200"}, [true, "gegenkonto"]],
      "a Konto saying no and an unknown Gegenkonto" =>
        [{konto: "66500", gegenkonto: "99999"}, [false, "konto"]],
      # Step 2, the cost center: a booking on a cost center that is not a unit's
      # own is not a unit's spending, and the accounts are not asked at all.
      "a cost center that is not a unit's own beats two accounts saying yes" =>
        [{cost_center_number: "Z1", konto: "1200", gegenkonto: "1200"}, [false, "cost_center"]],
      "a cost center that is not a unit's own is named before the accounts" =>
        [{cost_center_number: "Z1", konto: "66500", gegenkonto: "66500"}, [false, "cost_center"]],
      "the booking's own true beats a cost center that is not a unit's own" =>
        [{cost_center_number: "Z1", is_unit_budget: true, konto: "66500", gegenkonto: "66500"},
          [true, "booking"]],
      "a unit's own cost center leaves the accounts to decide" =>
        [{cost_center_number: "U1", konto: "1200", gegenkonto: "1200"}, [true, "konten"]],
      "a unit's own cost center does not save a booking from its Konto" =>
        [{cost_center_number: "U1", konto: "66500", gegenkonto: "1200"}, [false, "konto"]],
      "an unanswered cost-center flag leaves the accounts to decide" =>
        [{cost_center_number: "N1", konto: "1200", gegenkonto: "1200"}, [true, "konten"]],
      "a number naming no cost center leaves the accounts to decide" =>
        [{cost_center_number: "K9", konto: "66500", gegenkonto: "66500"}, [false, "konten"]],
      "no cost center at all leaves the accounts to decide" =>
        [{cost_center_number: nil, konto: "99999", gegenkonto: "99999"}, [true, "default"]]
    }.each do |description, (attrs, expected)|
      it description do
        record = booking(**attrs)

        expect(from_sql(record)).to eq(expected)
        expect(record.reload.unit_budget).to eq(expected)
      end
    end

    # The two master-data tables use disjoint number ranges, so ONE lookup covers
    # both: a Kreditor answers exactly as a Sachkonto does.
    it "reads a Personenkonto as readily as a Sachkonto" do
      record = booking(konto: "1200", gegenkonto: "700013")

      expect(from_sql(record)).to eq([false, "gegenkonto"])
      expect(record.reload.unit_budget).to eq([false, "gegenkonto"])
    end
  end

  describe "#unit_budget" do
    # A row that carries the columns answers from them -- that is what keeps a
    # table page at one query instead of two per row.
    it "reads the loaded columns rather than the accounts" do
      record = booking(konto: "66500", gegenkonto: "1200")
      row = described_class.with_unit_budget.find(record.id)

      expect(row).to have_attribute(:effective_is_unit_budget)
      expect(row.unit_budget).to eq([false, "konto"])
    end

    it "computes the answer for a booking loaded without them" do
      record = booking(konto: "66500", gegenkonto: "1200")

      plain = described_class.find(record.id)
      expect(plain).not_to have_attribute(:effective_is_unit_budget)
      expect(plain.unit_budget).to eq([false, "konto"])
    end
  end

  # What the cost center and the accounts say between them -- what the booking's
  # own flag overrides, and what the edit page's first select option names.
  describe "#automatic_unit_budget" do
    it "ignores the booking's own flag" do
      record = booking(konto: "66500", gegenkonto: "1200", is_unit_budget: true)

      expect(record.unit_budget).to eq([true, "booking"])
      expect(record.automatic_unit_budget).to eq([false, "konto"])
    end

    it "falls back to the default where neither number names an account" do
      record = booking(konto: "99999", gegenkonto: "99999",
        is_unit_budget: false)

      expect(record.automatic_unit_budget).to eq([true, "default"])
    end

    it "names the cost center where it is not a unit's own" do
      record = booking(cost_center_number: "Z1", konto: "1200", gegenkonto: "1200",
        is_unit_budget: true)

      expect(record.unit_budget).to eq([true, "booking"])
      expect(record.automatic_unit_budget).to eq([false, "cost_center"])
    end
  end

  # The wagon has no migration specs, so the two DATA steps of
  # 20260918100000_add_is_unit_budget_to_accounts are asserted here, through
  # their own predicate: a cost center whose NUMBER is one capital letter plus
  # digits is a unit's own, anything else is not. The UPDATE below is the
  # migration's first statement verbatim.
  describe "the seeded unit cost centers" do
    let!(:seeded) { WsjrdpCostCenter.create!(number: "A1", name: "Unit A1") }
    let!(:not_seeded) { WsjrdpCostCenter.create!(number: "9500", name: "Zentrale Beschaffung") }

    before do
      WsjrdpCostCenter.create!(number: "AB12", name: "Zwei Buchstaben")
      WsjrdpCostCenter.create!(number: "A1B", name: "Buchstabe am Ende")
      WsjrdpCostCenter.where("number ~ '^[A-Z][0-9]+$'").update_all(is_unit_cost_center: true)
    end

    # The pattern is about the NUMBER's shape -- one capital letter, then digits
    # to the end. The name plays no part in it.
    it "flags the unit-numbered cost centers and leaves the rest alone" do
      flagged = WsjrdpCostCenter.where(is_unit_cost_center: true).pluck(:number)

      expect(flagged).to include("A1")
      expect(flagged).not_to include("9500", "AB12", "A1B")
      expect(seeded.reload.is_unit_cost_center).to be true
      expect(not_seeded.reload.is_unit_cost_center).to be false
    end

    # What the flag then does to a booking: on the unit's cost center the
    # accounts decide, on the central one the cost center does.
    it "lets a booking on the unit cost center reach its accounts" do
      record = booking(cost_center_number: "A1", konto: "1200", gegenkonto: "1200")

      expect(from_sql(record)).to eq([true, "konten"])
    end

    it "keeps a booking on a central cost center out of the unit budget" do
      record = booking(cost_center_number: "9500", konto: "1200", gegenkonto: "1200")

      expect(from_sql(record)).to eq([false, "cost_center"])
      expect(record.reload.unit_budget).to eq([false, "cost_center"])
    end
  end

  # The scope is a select plus two joins, not a derived table: it therefore
  # composes with everything a bookings relation is otherwise built from.
  describe ".with_unit_budget" do
    it "keeps every ordinary booking column usable" do
      record = booking(konto: "1200", gegenkonto: "66500", posting_text: "Testbuchung",
        base_amount: 25)

      row = described_class.with_unit_budget.find(record.id)

      expect(row.buchungs_guid).to eq(record.buchungs_guid)
      expect(row.posting_text).to eq("Testbuchung")
      expect(row.booking_date).to eq(Date.new(2026, 1, 15))
      expect(row.signed_base_amount).to eq(25)
    end

    it "composes with an ordinary where, with the batch join and with paging" do
      wanted = booking(konto: "66500", gegenkonto: "66500", cost_center_number: "K1")
      booking(konto: "1200", gegenkonto: "1200", cost_center_number: "K2")

      rows = described_class.with_unit_budget.left_joins(:batch)
        .where(cost_center_number: "K1").order(:id).limit(5)

      expect(rows.map(&:id)).to eq([wanted.id])
      expect(rows.first.is_unit_budget_source).to eq("konten")
    end

    # The two aggregates a bookings table's footer takes
    # (Wsjrdp::ExpandableTableRows#total_count via Kaminari, and #total_sum):
    # both name their column, which replaces the select, so the two extra
    # expressions never reach the aggregate.
    it "still counts and sums" do
      booking(base_amount: 10)
      booking(base_amount: 30)

      expect(described_class.with_unit_budget.count(:all)).to eq(2)
      expect(described_class.with_unit_budget.sum(:signed_base_amount)).to eq(40)
    end

    # The one composition a derived table could not do: `legs` IS a derived table
    # aliased back to `datev_bookings`, and the account detail pages list their
    # bookings through it.
    it "composes with the legs of a booking" do
      record = booking(konto: "66500", gegenkonto: "1200", base_amount: 40)

      legs = described_class.legs.with_unit_budget.where(leg_account_number: "66500")

      expect(legs.map(&:id)).to eq([record.id])
      expect(legs.first.effective_is_unit_budget).to be false
      expect(legs.first.is_unit_budget_source).to eq("konto")
      expect(legs.first.signed_leg_amount).to eq(40)
    end

    # ORDER BY takes the same expression the rows select, so a sorted table and
    # its cells can never disagree.
    it "sorts by the effective value" do
      no = booking(konto: "66500", gegenkonto: "66500")
      yes = booking(konto: "1200", gegenkonto: "1200")

      sorted = described_class.with_unit_budget
        .reorder(Arel.sql("#{described_class::EFFECTIVE_IS_UNIT_BUDGET_SQL} ASC, id ASC"))

      expect(sorted.map(&:id)).to eq([no.id, yes.id])
    end
  end
end
