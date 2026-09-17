# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# Whether the Moss receipt carries its explanation paragraph. An absent key
# means it does, so the false has to survive being written -- and clearing the
# flag has to remove the key rather than leave a null behind.
describe "Person deregistration refund receipt explanation flag" do
  let(:person) { people(:yp_a_1) }
  let(:key) { "deregistration_refund_receipt_show_default_explanation" }

  it "is shown while nothing is stored" do
    expect(person.additional_info).not_to have_key(key)
    expect(person.deregistration_refund_receipt_show_default_explanation).to be_nil
    expect(person).to be_deregistration_refund_receipt_show_default_explanation
  end

  it "keeps an explicit false" do
    person.update!(deregistration_refund_receipt_show_default_explanation: false)

    expect(person.reload.additional_info[key]).to be(false)
    expect(person.deregistration_refund_receipt_show_default_explanation).to be(false)
    expect(person).not_to be_deregistration_refund_receipt_show_default_explanation
  end

  it "keeps an explicit true as the true it is" do
    person.update!(deregistration_refund_receipt_show_default_explanation: true)

    expect(person.reload.additional_info[key]).to be(true)
    expect(person).to be_deregistration_refund_receipt_show_default_explanation
  end

  it "removes the key when the flag is cleared" do
    person.update!(deregistration_refund_receipt_show_default_explanation: false)

    person.update!(deregistration_refund_receipt_show_default_explanation: nil)

    expect(person.reload.additional_info).not_to have_key(key)
    expect(person).to be_deregistration_refund_receipt_show_default_explanation
  end
end
