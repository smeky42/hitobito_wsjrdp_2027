# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# What a person paid towards their fee, on paper: the Kontoauszug page of the
# scripts' deregistration confirmation. Booked entries only, nothing internal
# (no comments, no pre-notifications, no entries that move no money).
describe Wsjrdp2027::FeeStatement do
  let(:person) { people(:yp_a_1) }
  let(:admin) { people(:admin) }

  def booked_entry(amount_cents: 40_000, description: "Teilnahmebeitrag", comment: "",
    value_date: Date.new(2026, 2, 1), booking_date: value_date)
    AccountingEntry.create!(subject: person, author: admin, amount_cents: amount_cents,
      amount_currency: "EUR", description: description, comment: comment,
      value_date: value_date, booking_date: booking_date)
  end

  # A pre-notification needs a payment initiation it belongs to; nothing here
  # is written to the database, the statement only reads.
  def pre_notification(payment_status:, try_skip: false)
    WsjrdpDirectDebitPreNotification.new(
      subject: person, author: admin, amount_cents: 40_000, amount_currency: "EUR",
      description: "Lastschrifteinzug", payment_status: payment_status, try_skip: try_skip,
      dbtr_name: "Muster", dbtr_iban: "DE02120300000000202051",
      collection_date: Date.new(2026, 3, 1), created_at: Time.zone.local(2026, 2, 15)
    )
  end

  def statement_for(entries)
    described_class.new(person.reload, entries: entries)
  end

  describe "the head of the page" do
    it "names the person, the day and the money" do
      booked_entry
      statement = statement_for([])

      expect(statement.title).to eq("Kontoauszug YP #{person.id} YP1 UnitA")
      expect(statement.role_id_name).to eq("YP #{person.id} YP1 UnitA")
      expect(statement.to_sys_inputs[:role_id_name]).to eq("YP #{person.id} YP1 UnitA")
      expect(statement.statement_date_text).to eq(I18n.l(Date.current))
      # The scripts' format: ",—" for whole euros, a non-breaking space
      # before the euro sign.
      expect(statement.balance_text).to eq("400,— €")
    end
  end

  describe "the rows" do
    it "writes a booked entry plainly" do
      row = statement_for([booked_entry]).rows.first

      expect(row.keys).to eq(%w[date description short_dbtr amount])
      expect(row["date"]).to eq("01.02.2026")
      expect(row["description"]).to eq("Teilnahmebeitrag")
      expect(row["amount"]).to eq("400,— €")
    end

    it "writes the cents where there are any" do
      row = statement_for([booked_entry(amount_cents: 123_456)]).rows.first

      expect(row["amount"]).to eq("1.234,56 €")
    end

    # A pre-notification is not a booking, whatever its state.
    it "leaves pre-notifications out" do
      entries = [
        pre_notification(payment_status: "pre_notified"),
        pre_notification(payment_status: "pre_notified", try_skip: true),
        pre_notification(payment_status: "skipped"),
        booked_entry
      ]

      expect(statement_for(entries).rows.pluck("description")).to eq(["Teilnahmebeitrag"])
    end

    it "leaves an entry that moves no money out" do
      entries = [booked_entry(amount_cents: 0, description: "Statusänderung"), booked_entry]

      expect(statement_for(entries).rows.pluck("description")).to eq(["Teilnahmebeitrag"])
    end

    # The scripts' order: value date, booking date, id -- all descending.
    it "sorts newest first, by value date, then booking date, then id" do
      a = booked_entry(description: "A", value_date: Date.new(2026, 1, 1))
      b = booked_entry(description: "B", value_date: Date.new(2026, 3, 1))
      c = booked_entry(description: "C", value_date: Date.new(2026, 3, 1),
        booking_date: Date.new(2026, 2, 15))
      d = booked_entry(description: "D", value_date: Date.new(2026, 3, 1))

      expect(statement_for([a, b, c, d].shuffle).rows.pluck("description")).to eq(%w[D B C A])
    end

    it "carries what the account was debited from" do
      entry = booked_entry
      entry.update!(dbtr_name: "Muster", dbtr_iban: "DE02120300000000202051")

      expect(statement_for([entry]).rows.first["short_dbtr"]).to include("Muster")
    end

    # A comment is internal, whatever the page shows to whom: it is not a
    # column, and it does not even reach the template.
    it "carries no comment" do
      statement = statement_for([booked_entry(comment: "interner Kommentar")])

      expect(statement.rows.first).not_to have_key("comment")
      expect(statement.to_sys_inputs.values.join).not_to include("interner Kommentar")
    end

    it "hands every value to typst as a String" do
      rows = statement_for([booked_entry]).rows

      expect(rows.first.values).to all(be_a(String))
      expect(JSON.parse(statement_for([booked_entry]).to_sys_inputs[:entries])).to eq(rows)
    end
  end

  describe "#file_name" do
    it "names the person and what the document is" do
      expect(statement_for([]).file_name)
        .to eq("WSJ27 Beitragszahlungen YP #{person.id} YP1 UnitA.pdf")
    end

    it "replaces what a file name must not carry" do
      person.update!(last_name: "Muster/Beispiel")

      expect(statement_for([]).file_name).to include("Muster_Beispiel")
    end
  end

  describe "#to_pdf" do
    it "compiles the template" do
      pdf = statement_for([booked_entry, booked_entry(description: "Zweite Rate")]).to_pdf

      expect(pdf).to start_with("%PDF")
      expect(pdf.bytesize).to be > 1_000
    end

    # Whatever somebody typed into a description is text, never markup: the
    # compile must neither fail nor evaluate anything.
    it "compiles a description that looks like typst markup, as text" do
      injection = "#emph[x] *y* $z$ ] \" ; #eval(\"1\")"
      entry = booked_entry(description: injection, comment: injection)
      statement = statement_for([entry])

      expect(statement.rows.first["description"]).to eq(injection)
      expect(JSON.parse(statement.to_sys_inputs[:entries]).first["description"]).to eq(injection)

      pdf = statement.to_pdf
      expect(pdf).to start_with("%PDF")
      File.binwrite("/tmp/fee_statement_injection.pdf", pdf) if ENV["WRITE_STATEMENT_PDF"]
    end
  end

  # No template evaluates a string as Typst code -- that is the one rule these
  # documents live by, and it is cheap to keep an eye on.
  describe "the templates" do
    it "evaluate nothing" do
      Dir[Wsjrdp2027::TypstDocument.typst_dir.join("*.typ")].each do |path|
        expect(File.read(path)).not_to include("eval("), "#{File.basename(path)} calls eval"
      end
    end
  end
end
