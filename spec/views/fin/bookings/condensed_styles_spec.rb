# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# fin/bookings/_condensed_styles addresses the columns of the condensed bookings
# table through the css class the widget puts on their cells --
# "<css_prefix>-<key>", the prefix being "bkcol". That is a reference to
# Fin::DatevBookingsColumns which no compiler and no test of the rendered page
# can see: a stylesheet just does not match, and the table still renders. It has
# gone stale before (rules on columns named "amount" and "description" that had
# been renamed), which cost the description its wrapping.
#
# So the reference is checked here: every bkcol class named in the partial must
# be a column key that actually exists.
describe "fin/bookings/_condensed_styles" do
  let(:partial) do
    HitobitoWsjrdp2027::Wagon.root.join("app/views/fin/bookings/_condensed_styles.html.haml")
  end

  # Only the selectors, i.e. a class with its leading dot -- the prose in the
  # head comment talks about the naming scheme without one.
  let(:styled_keys) { partial.read(encoding: "UTF-8").scan(/\.bkcol-([A-Za-z0-9_]+)/).flatten.uniq }

  it "styles columns that exist" do
    expect(styled_keys).to be_present
    unknown = styled_keys.reject { |key| Fin::DatevBookingsColumns::COLUMNS.key?(key) }
    expect(unknown).to be_empty,
      "fin/bookings/_condensed_styles styles bkcol classes that are no column key of " \
      "Fin::DatevBookingsColumns: #{unknown.join(", ")}"
  end

  # The two columns the layout actually hangs on: the amount reserves its share
  # of a fixed layout, the posting text is the wrapping leftover column.
  it "covers the columns the condensed layout depends on" do
    expect(styled_keys).to include("signed_base_amount", "posting_text")
  end

  # The widget's shared styles are the kit: they may size a condensed table, but
  # they must not know this dataset's columns.
  it "keeps the dataset's columns out of the shared widget styles" do
    widget = HitobitoWsjrdp2027::Wagon.root
      .join("app/views/shared/wsjrdp/_expandable_table_styles.html.haml")
    expect(widget.read(encoding: "UTF-8")).not_to match(/\.bkcol-/)
  end
end
