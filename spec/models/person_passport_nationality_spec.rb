# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The nationality is stored as ISO codes; the form chooses them from a list.
# The model is lenient: an entry that is no code is kept as it is.
describe Person do
  let(:person) { people(:yp_a_1) }

  it "saves the chosen countries as codes, any name turned into its code" do
    person.update!(passport_nationality_codes: ["", "DE", "AT", "Germany"])

    expect(person.reload.passport_nationality).to eq("DE, AT")
    expect(person.passport_nationality_codes).to eq(%w[DE AT])
  end

  it "keeps an entry it does not know, and an empty choice clears the list" do
    person.update!(passport_nationality_codes: %w[DE Elbisch])
    expect(person.reload.passport_nationality).to eq("DE, Elbisch")

    person.update!(passport_nationality_codes: [""])
    expect(person.reload.passport_nationality).to be_nil
  end
end
