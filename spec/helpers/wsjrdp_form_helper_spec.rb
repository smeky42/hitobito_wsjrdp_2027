# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe WsjrdpFormHelper do
  let(:view) do
    Class.new do
      include WsjrdpFormHelper
      attr_accessor :permitted_attrs
    end.new
  end

  it "counts a jsonb key as permitted whether it is listed flat or nested" do
    view.permitted_attrs = [:comment, :excluded_from_fee_reconciliation]
    expect(view.permitted_attr?(:excluded_from_fee_reconciliation)).to be(true)

    view.permitted_attrs = [:comment, {additional_info: [:excluded_from_fee_reconciliation]}]
    expect(view.permitted_attr?(:excluded_from_fee_reconciliation)).to be(true)
    expect(view.permitted_attr?(:comment)).to be(true)
    expect(view.permitted_attr?(:amount_eur)).to be(false)
  end
end
