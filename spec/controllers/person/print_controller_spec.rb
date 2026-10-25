# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe Person::PrintController, type: :controller do
  let(:yp) { people(:yp_a_1) }

  around { |example| Dir.mktmpdir { |dir| @dir = dir; example.run } } # rubocop:disable Style/Semicolon

  before do
    sign_in(yp)
    yp.update_columns(status: "registered", print_at: Date.new(2025, 9, 1))
    allow_any_instance_of(described_class).to receive(:printable).and_return(true)
    allow_any_instance_of(described_class).to receive(:file_folder).and_return("#{@dir}/")
    pdf = double(render_file: nil)
    allow(pdf).to receive(:render_file) { |path| File.write(path, "%PDF") }
    allow(Wsjrdp2027::Export::Pdf::Registration).to receive(:new_pdf).and_return(pdf)
  end

  it "dates the SEPA mandate on submitting the registration" do
    get :submit, params: {id: yp.id}

    expect(yp.reload).to have_attributes(status: "printed", print_at: Time.zone.today)
    expect(yp.additional_info["sepa_mandate_date"]).to eq(Time.zone.today.iso8601)
  end
end
