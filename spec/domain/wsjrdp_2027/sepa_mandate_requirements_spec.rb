# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Standalone: a pure module, no Rails boot.
require "active_support/core_ext/object/blank"
module Wsjrdp2027; end
require_relative "../../../app/domain/wsjrdp_2027/sepa_mandate_requirements"

describe Wsjrdp2027::SepaMandateRequirements do
  let(:complete) do
    {first_name: "Erika", last_name: "Mustermann", birthday: Date.new(2010, 5, 1), town: "Musterstadt",
     sepa_name: "Erika Mustermann", sepa_address: "Musterstraße 1", sepa_iban: "DE02120300000000202051",
     yme_list: [:installment]}
  end

  def person(**attrs) = Struct.new(*complete.keys, keyword_init: true).new(**complete.merge(attrs))

  it "misses nothing of a complete person" do
    expect(described_class.missing(person)).to eq([])
  end

  it "names the blank fields and a missing plan" do
    expect(described_class.missing(person(town: "", sepa_iban: nil, yme_list: nil)))
      .to eq(%i[town sepa_iban payment_plan])
  end
end
