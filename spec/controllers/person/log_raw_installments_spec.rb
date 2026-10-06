# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The person log renders a change of the active installment plan
# (wsjrdp_raw_installments_eur) written out like the payment plans list, through
# Wsjrdp2027::PaperTrail::VersionDecorator#attribute_change. The log page is
# used instead of a decorator spec, see log_finance_group_ids_spec.rb.
describe Person::LogController do
  render_views

  let(:person) { people(:yp_a_1) }

  before { sign_in(people(:admin)) }

  def log = get(:index, params: {group_id: person.primary_group_id, id: person.id})

  def changes_html = Nokogiri::HTML(response.body).css(".log-infos").to_html

  it "renders the plan written through the model" do
    with_versioning do
      person.update!(wsjrdp_raw_installments_eur: [2026, 0, BigDecimal("312.5"), 500],
        wsjrdp_installments_issue: "HELP-1", wsjrdp_installments_comment: "Vereinbarung",
        wsjrdp_installments_payment_method: "credit_transfer")
    end

    log

    expect(response).to be_successful
    expect(changes_html).to include("Ratenplan").and include("2026-02: 312,50€, 2026-03: 500€")
    expect(changes_html).to include("HELP-1")
    expect(changes_html).to include("Zahlungsart Ratenplan").and include("Überweisung")
    expect(changes_html).not_to include("credit_transfer")
    expect(changes_html).not_to include("Vereinbarung")
    expect(changes_html).not_to include("e3")
  end
end
