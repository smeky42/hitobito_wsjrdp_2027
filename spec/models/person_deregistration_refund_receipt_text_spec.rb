# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# What the Moss receipt says above its table. An absent key is what "the
# default greeting" looks like in the store, so emptying the field has to
# remove it rather than leave an empty string behind.
describe "Person deregistration refund receipt text" do
  let(:person) { people(:yp_a_1) }

  it "is absent until something is written" do
    expect(person.additional_info).not_to have_key("deregistration_refund_receipt_text")
    expect(person.deregistration_refund_receipt_text).to be_nil
  end

  it "keeps the text with its line structure" do
    person.update!(deregistration_refund_receipt_text: "Hallo Team,\n\nbitte zurück:\nsoweit klar")

    expect(person.reload.deregistration_refund_receipt_text)
      .to eq("Hallo Team,\n\nbitte zurück:\nsoweit klar")
  end

  it "strips what surrounds the text" do
    person.update!(deregistration_refund_receipt_text: "  Hallo Team\n\n")

    expect(person.reload.deregistration_refund_receipt_text).to eq("Hallo Team")
  end

  it "drops the key when the text is blanked" do
    person.update!(deregistration_refund_receipt_text: "Hallo Team")

    person.update!(deregistration_refund_receipt_text: "")

    expect(person.reload.additional_info).not_to have_key("deregistration_refund_receipt_text")
    expect(person.deregistration_refund_receipt_text).to be_nil
  end

  it "drops the key for whitespace alone" do
    person.update!(deregistration_refund_receipt_text: "Hallo Team")

    person.update!(deregistration_refund_receipt_text: "   \n ")

    expect(person.reload.additional_info).not_to have_key("deregistration_refund_receipt_text")
  end
end
