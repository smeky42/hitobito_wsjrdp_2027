# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The two free-text columns: `comment` is written by the app (import, matching),
# `user_comment` by a human. Both are NOT NULL DEFAULT '', so nothing ever has
# to distinguish NULL from "no comment".
describe DatevBooking do
  def booking(attrs = {})
    defaults = {buchungs_guid: SecureRandom.uuid,
                booking_date: Date.new(2026, 1, 15),
                base_amount: 10, transaction_amount: 10,
                debit_credit: "D",
                account_number: "18000", offsetting_account_number: "66500",
                account_kind: "BANK", offsetting_account_kind: "EXPENSE"}
    described_class.create!(defaults.merge(attrs))
  end

  it "defaults both comments to an empty string" do
    expect(described_class.new.comment).to eq("")
    expect(described_class.new.user_comment).to eq("")
    expect(booking.reload).to have_attributes(comment: "", user_comment: "")
  end

  it "keeps the two comments apart" do
    b = booking(comment: "Beleg maschinell zugeordnet")
    b.update!(user_comment: "Rückfrage offen")
    expect(b.reload).to have_attributes(comment: "Beleg maschinell zugeordnet",
      user_comment: "Rückfrage offen")
  end
end
