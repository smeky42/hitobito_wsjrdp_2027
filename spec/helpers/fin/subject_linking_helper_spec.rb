# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The rule behind every person-linking button: :update on the transaction class
# AND on the person (the server checks the same in SubjectLinking).
describe Fin::SubjectLinkingHelper do
  let(:person) { people(:cmt_leader) }

  def allow_update(on_class:, on_person:)
    allow(helper).to receive(:can?).with(:update, MossBooking).and_return(on_class)
    allow(helper).to receive(:can?).with(:update, person).and_return(on_person)
  end

  it "offers the buttons with :update on the booking and on the person" do
    allow_update(on_class: true, on_person: true)
    expect(helper.may_link_subject?(MossBooking, person)).to be true
  end

  it "hides them without :update on the person" do
    allow_update(on_class: true, on_person: false)
    expect(helper.may_link_subject?(MossBooking, person)).to be false
  end

  it "hides them without :update on the booking" do
    allow_update(on_class: false, on_person: true)
    expect(helper.may_link_subject?(MossBooking, person)).to be false
  end

  it "hides them when there is no person" do
    expect(helper.may_link_subject?(MossBooking, nil)).to be false
  end
end
