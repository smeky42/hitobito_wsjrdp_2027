# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe Wsjrdp2027::DeregistrationFormDocument do
  let(:person) { people(:yp_a_1) }
  let(:admin) { people(:admin) }
  let(:token) do
    ServiceToken.create!(layer: groups(:root), name: "deregistration", permission: "layer_and_below_full",
      acting_person: admin, scopes: %w[people people:log])
  end
  let(:upload_root) { Pathname(Dir.mktmpdir("wsjrdp-deregistration-document")) }

  after { FileUtils.rm_rf(upload_root) }

  before do
    allow(Wsjrdp2027::DocumentStore).to receive(:root).and_return(upload_root)
    allow_any_instance_of(Wsjrdp2027::DeregistrationForm).to receive(:to_pdf).and_return("%PDF-1.4\n%stub\n")
    allow_any_instance_of(Wsjrdp2027::DeregistrationForm).to receive(:to_png).and_return("\x89PNG\r\n\x1a\nstub".b)
    person.update!(deregistration_effective_date: Date.new(2026, 12, 31), deregistration_actual_compensation_cents: 15_000)
    Wsjrdp2027::DeregistrationForm.new(person.reload).record_creation!
  end

  def store! = described_class.new(person.reload, author: admin, service_token: token).store!

  def book_payment
    AccountingEntry.create!(subject: person, author: admin, amount_cents: 20_000, amount_currency: "EUR",
      description: "Teilnahmebeitrag", value_date: Date.new(2026, 2, 1), booking_date: Date.new(2026, 2, 1))
  end

  it "keeps the PDF with its first page as a picture, as the row's form" do
    document = store!

    aggregate_failures do
      expect(person.reload.deregistration.sent_form_document).to eq(document)
      expect(document).to have_attributes(key: "deregistration", secondary_key: "form", origin: "api",
        origin_service_token: token, content_type: "application/pdf")
      expect(document.derivatives.sole).to have_attributes(derivation_key: "thumbnail", content_type: "image/png",
        secondary_key: "form", filename: document.filename.sub(/\.pdf\z/, ".png"))
    end
  end

  it "takes the kept form while it is fresh, and the sent one whatever the data say" do
    first = store!

    expect { expect(store!).to eq(first) }.not_to change(WsjrdpDocument, :count)

    person.reload.deregistration.update_columns(form_sent_at: Time.current)
    book_payment
    expect { expect(store!).to eq(first) }.not_to change(WsjrdpDocument, :count)
  end

  it "keeps a new version where the data changed since, the old one superseded" do
    first = store!
    book_payment

    expect(store!).not_to eq(first)
    expect(first.reload.status).to eq("superseded")
  end

  it "keeps a new version where the kept one is gone" do
    first = store!
    first.update_columns(file_status: WsjrdpDocument::FILE_MISSING)

    expect(store!).not_to eq(first)
    expect(first.reload.status).to eq("superseded")
  end
end
