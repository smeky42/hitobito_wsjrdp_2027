# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe AccountingEntry do
  describe "#excluded_from_fee_reconciliation" do
    let(:entry) { AccountingEntry.new }

    it "reads an absent key as false" do
      expect(entry.excluded_from_fee_reconciliation).to be(false)
      expect(entry).not_to be_excluded_from_fee_reconciliation
    end

    it "reads a set key as true" do
      entry.excluded_from_fee_reconciliation = true

      expect(entry.excluded_from_fee_reconciliation).to be(true)
    end

    # A bare double negation would read "0" as true.
    it "reads a string the store may carry as the boolean it means" do
      entry.additional_info = {"excluded_from_fee_reconciliation" => "0"}
      expect(entry.excluded_from_fee_reconciliation).to be(false)

      entry.additional_info = {"excluded_from_fee_reconciliation" => "1"}
      expect(entry.excluded_from_fee_reconciliation).to be(true)
    end
  end
end
