# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The link a Buchhaltung detail ("In Buchungen-Ansicht öffnen") points at: the
# Buchungen listing carries its whole filter in the ?f= param as Rison with
# SHORT keys (doc/wsjrdp/generic_filter_builder.md §2.8), so the helper encodes
# a long-form CNF tree through the bookings page's own schema.
#
# All account / cost-center numbers here are invented.
describe Fin::BookkeepingHelper do
  # The wire value of the built path, decoded back into the long-form tree the
  # helper was given -- the round trip is what the three detail links rely on.
  def decoded_tree(path)
    wire = CGI.unescape(path[/[?&]f=([^&]*)/, 1].to_s)
    Fin::DatevBookingsFilterSchema
      .decode(wire, schema: Fin::DatevBookingsFilterSchema.bound)
      .as_json
  end

  describe "#bookings_filter_path" do
    it "encodes a ledger-account condition as the schema's short keys" do
      path = helper.bookings_filter_path([[["konto", "in", "4100"]]])
      expect(path).to eq("/fin/bookkeeping/bookings?f=!(!(!(k,in,'4100')))")
      expect(decoded_tree(path)).to eq([[["konto", "in", "4100"]]])
    end

    it "encodes a cost-center condition" do
      path = helper.bookings_filter_path([[["cost_center", "in", "3150"]]])
      expect(path).to eq("/fin/bookkeeping/bookings?f=!(!(!(cc,in,'3150')))")
      expect(decoded_tree(path)).to eq([[["cost_center", "in", "3150"]]])
    end

    # A supplier is looked for on EITHER side of the booking, so the attribute
    # is "Konto oder Gegenkonto" (kgk), not Konto.
    it "encodes a supplier condition on either side of the booking" do
      path = helper.bookings_filter_path([[["any_account", "in", "700101"]]])
      expect(path).to eq("/fin/bookkeeping/bookings?f=!(!(!(kgk,in,'700101')))")
      expect(decoded_tree(path)).to eq([[["any_account", "in", "700101"]]])
    end

    # Tolerant encoding: a tree the schema does not know yields no wire value at
    # all, and the link then goes to the unfiltered listing rather than to a
    # broken URL.
    it "falls back to the plain listing when nothing survives encoding" do
      expect(helper.bookings_filter_path([[["typo_attribute", "in", "1"]]]))
        .to eq("/fin/bookkeeping/bookings")
    end

    # The Buchungen page hides these attributes, so a link may not name one.
    it "drops an attribute the Buchungen page excludes" do
      expect(helper.bookings_filter_path([[["sphere", "in", "3"]]]))
        .to eq("/fin/bookkeeping/bookings")
    end
  end
end
