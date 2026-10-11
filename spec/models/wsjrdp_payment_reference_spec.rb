# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe WsjrdpPaymentReference do
  let(:code) { "RF75K7M3QX9PNFK3" }
  let(:codeword) { "K7M3QX9PNFK3" }

  def payment_code(**attrs) = described_class.create!(payment_code: code, codeword: codeword, **attrs)

  # Inserts past the model's validation, so the database alone decides.
  def insert(**attrs) = described_class.new(payment_code: code, codeword: codeword, **attrs).save!(validate: false)

  it "has the defaults of the table" do
    created = payment_code.reload

    expect(created).to have_attributes(payment_code_type: "rf", codeword_scheme: "crockford_rs", data_length: 8,
      parity_length: 4, rs_field_exponent: 5, rs_primitive_polynomial: 0x25, rs_generator: 2, rs_fcr: 1,
      status: "available", assigned_at: nil, origin: "script", comment: "", additional_info: {})
    expect(created.created_at).to be_present
  end

  describe "the rf form" do
    it "takes RF, two digits and the codeword" do
      expect { payment_code }.not_to raise_error
    end

    {
      "another prefix" => "XX75K7M3QX9PNFK3",
      "letters as check digits" => "RFAAK7M3QX9PNFK3",
      "another codeword" => "RF75K7M3QX9PNFK4",
      "the printed form" => "RF75 K7M3 QX9P NFK3"
    }.each do |what, wrong|
      it "refuses #{what}, in the database and in the model" do
        expect(described_class.new(payment_code: wrong, codeword: codeword)).not_to be_valid
        expect { insert(payment_code: wrong) }
          .to raise_error(ActiveRecord::StatementInvalid, /chk_wsjrdp_payment_references_rf_form/)
      end
    end

    it "is not asked of another type" do
      expect { insert(payment_code_type: "other", payment_code: "ANYTHING") }.not_to raise_error
    end
  end

  it "keeps payment codes and codewords unique" do
    payment_code

    expect { insert }.to raise_error(ActiveRecord::RecordNotUnique)
    expect { insert(payment_code_type: "other", payment_code: "OTHER") }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "is found from its payment notices, and finds them" do
    entry = payment_code
    notice = WsjrdpPaymentNotice.create!(subject_id: people(:yp_a_1).id, amount: "-10", payment_code: code,
      description: "Rückzahlung #{code}", payment_reference: entry)

    expect(notice.payment_reference).to eq(entry)
    expect(entry.payment_notices).to eq([notice])
    expect(entry.destroy).to be(false)
  end

  it "lists available and assigned codes" do
    available = payment_code
    assigned = described_class.create!(payment_code: "RF04000000000000", codeword: "000000000000", status: "assigned")

    expect(described_class.available).to eq([available])
    expect(described_class.assigned).to eq([assigned])
  end

  describe ".assign!" do
    it "hands out the oldest available reference" do
      older = described_class.generate!(2).first

      assigned = described_class.assign!

      expect(assigned).to eq(older)
      expect(assigned.reload).to have_attributes(status: "assigned", origin: "wagon")
      expect(assigned.assigned_at).to be_present
      expect(described_class.available.count).to eq(1)
    end

    it "makes a reference itself when none is available" do
      payment_code(status: "assigned")

      assigned = described_class.assign!

      expect(assigned).to have_attributes(status: "assigned", origin: "wagon")
      expect(Wsjrdp2027::PaymentCode.valid?(assigned.payment_code)).to be(true)
      expect(described_class.count).to eq(2)
    end

    it "never hands out a void reference" do
      payment_code(status: "void")

      expect(described_class.assign!.payment_code).not_to eq(code)
    end
  end

  describe ".generate!" do
    it "makes valid available references, far enough from each other and the existing ones" do
      payment_code
      made = described_class.generate!(20)

      expect(made.map(&:status).uniq).to eq(%w[available])
      expect(made.map(&:origin).uniq).to eq(%w[wagon])
      made.each { |reference| expect(Wsjrdp2027::PaymentCode.valid?(reference.payment_code)).to be(true) }
      codewords = described_class.pluck(:codeword)
      codewords.each do |codeword|
        hamming, = Wsjrdp2027::PaymentCode.distances(codeword, codewords - [codeword])
        expect(hamming).to be >= Wsjrdp2027::PaymentCode::MIN_HAMMING_DISTANCE
      end
    end

    it "knows how many make up the pool and when the stock is low" do
      described_class.generate!(3)

      expect(described_class.missing_for_pool).to eq(described_class::POOL_SIZE - 3)
      expect(described_class).to be_low_stock
    end
  end

  describe "the generation lock" do
    it "is taken when codes are made, and held until the transaction ends" do
      held = lambda do
        WsjrdpPaymentReference.connection.select_value(<<~SQL).to_i
          SELECT count(*) FROM pg_locks
           WHERE locktype = 'advisory' AND pid = pg_backend_pid()
             AND objid = #{described_class::GENERATION_LOCK_KEY}
        SQL
      end
      inside = nil
      described_class.with_generation_lock { inside = held.call }

      expect(inside).to eq(1)
      expect { described_class.generate!(1) }.to change(described_class, :count).by(1)
    end
  end

  describe "a payment notice" do
    it "takes its code from the stock" do
      described_class.generate!(1)
      notice = WsjrdpPaymentNotice.new(subject_id: people(:yp_a_1).id, amount: "-10", description: "Rückzahlung")

      reference = notice.assign_payment_reference!
      notice.save!

      expect(notice.reload).to have_attributes(payment_reference_id: reference.id, payment_code: reference.payment_code)
    end
  end

  it "prints its code in groups of four" do
    expect(payment_code.printed_code).to eq("RF75 K7M3 QX9P NFK3")
  end
end
