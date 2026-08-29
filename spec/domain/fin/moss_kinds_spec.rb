# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The VISUAL half of the Moss kind vocabulary: one icon and one CSS class per
# kind of moss_transactions.
#
# Two invariants live HERE and nowhere else, because Fin::MossKinds deliberately
# names neither of the two things it has to agree with:
#
#   * the KEYS are Fin::MossTransactionsFilterSchema::KINDS, in that order --
#     naming the constant in the module would pull the whole filter schema into
#     every request that only wants an icon;
#   * the SLUG in each class name is the value the DATABASE generates into
#     moss_transactions.expense_type -- the module derives it from its own class
#     name, so only a real, saved row proves the two spell the kind alike.
describe Fin::MossKinds do
  # Icon, CSS class and slug per kind, spelled out instead of derived from the
  # module under test: a renamed icon or a mistyped class name is exactly what
  # this table is here to catch.
  let(:expected) do
    {"MossCardTransaction" => ["credit-card", "moss-kind-card_transaction", "card_transaction"],
     "MossReimbursement" => ["hand-holding-usd", "moss-kind-reimbursement", "reimbursement"],
     "MossInvoice" => ["file-invoice", "moss-kind-invoice", "invoice"],
     "MossTopUp" => ["piggy-bank", "moss-kind-top_up", "top_up"]}
  end

  let(:kinds) { described_class::STYLE.keys }

  # The smallest transaction of `type` the table accepts, read back so the
  # generated expense_type comes from Postgres rather than from Ruby.
  def transaction(type)
    MossTransaction.create!(type: type, moss_transaction_uuid: SecureRandom.uuid,
      signed_total_base_amount: 0, currency: "EUR").reload
  end

  it "marks exactly the Moss section's kinds, in the Moss section's order" do
    expect(kinds).to eq(Fin::MossTransactionsFilterSchema::KINDS)
  end

  it "gives every kind its icon, its CSS class and its slug" do
    marking = kinds.to_h do |kind|
      [kind, [described_class.icon(kind), described_class.css_class(kind), described_class.slug(kind)]]
    end
    expect(marking).to eq(expected)
  end

  it "spells the slug exactly as the database generates expense_type" do
    generated = kinds.to_h { |kind| [kind, transaction(kind).expense_type] }
    expect(generated).to eq(kinds.to_h { |kind| [kind, described_class.slug(kind)] })
  end

  # The lookup goes through to_s, so a row's own class is as good a key as its
  # type string -- which is what the wallet's row_class and the chip pass.
  it "accepts a kind's class as well as its name" do
    expect(described_class.icon(MossTopUp)).to eq(described_class.icon("MossTopUp"))
    expect(described_class.css_class(MossInvoice)).to eq(described_class.css_class("MossInvoice"))
  end

  # A new STI subclass must be given its marking here rather than rendering as
  # an unmarked, colourless row that silently looks like "no kind".
  it "raises for a kind it does not know" do
    expect { described_class.icon("MossSomethingNew") }.to raise_error(KeyError)
    expect { described_class.css_class(nil) }.to raise_error(KeyError)
    expect { described_class.slug("") }.to raise_error(KeyError)
  end
end
