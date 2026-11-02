# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The count with its sum and the breakdown of its amounts
# (Fin::PaymentsHelper#payment_count_with_breakdown). All amounts here are
# invented.
describe Fin::PaymentsHelper do
  let(:amounts) { [[40_000, 3], [30_000, 2], [12_550, 1]] }

  def render(count, amounts, **options)
    Capybara.string(helper.payment_count_with_breakdown(count, "Σ 1.025,50 €", amounts, **options))
  end

  it "shows a count of 0 alone" do
    expect(helper.payment_count_with_breakdown(0, "Σ 0,00 €", [])).to eq("0")
  end

  it "shows no breakdown for a sum of one amount" do
    expect(render(3, [[40_000, 3]])).to have_no_css(".payment-breakdown")
  end

  it "shows the first amounts and keeps the rest behind a more button" do
    html = render(6, amounts, limit: 2)

    expect(html).to have_css(".payment-breakdown[data-step='2'] .payment-breakdown-item:not([hidden])", count: 2)
    expect(html).to have_css(".payment-breakdown-item[hidden]", visible: :hidden, text: "1×\u00A0125,50\u202F€")
    expect(html).to have_button(I18n.t("fin.payments.breakdown_more"))
  end

  it "has no more button when every amount shows" do
    html = render(6, amounts)

    expect(html).to have_css(".payment-breakdown", text: "3×\u00A0400\u202F€ · 2×\u00A0300\u202F€ · 1×\u00A0125,50\u202F€")
    expect(html).to have_no_button(I18n.t("fin.payments.breakdown_more"))
  end
end
