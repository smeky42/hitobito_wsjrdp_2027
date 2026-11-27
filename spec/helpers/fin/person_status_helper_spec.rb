# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe Fin::PersonStatusHelper do
  def person(contract, status) = Person.new(contract_status: contract, status: status)

  def second_word(html) = Capybara.string(html).first(".fin-status-other", minimum: 0)&.text

  it "tells the pairs of contract and status that go together" do
    matching = [%w[none reviewed], %w[confirmed confirmed], %w[ended deregistered]]
    other = [%w[confirmed printed], %w[confirmed deregistration_noted], %w[replacement_pending reviewed],
      %w[ended reviewed], %w[none deregistered]]

    expect(matching.map { |pair| helper.fin_status_and_contract_match?(person(*pair)) }).to all(be(true))
    expect(other.map { |pair| helper.fin_status_and_contract_match?(person(*pair)) }).to all(be(false))
  end

  it "names the other one where the two do not go together and its column is hidden" do
    mismatch = person("confirmed", "deregistration_noted")

    expect(second_word(helper.fin_person_cell("contract", mismatch, %w[contract]))).to eq "Abmeldung"
    expect(second_word(helper.fin_person_cell("status", mismatch, %w[status]))).to eq "in Kraft"
    expect(second_word(helper.fin_person_cell("status", mismatch, %w[contract status]))).to be_nil
    expect(second_word(helper.fin_person_cell("status", person("confirmed", "confirmed"), %w[status]))).to be_nil
  end
end
