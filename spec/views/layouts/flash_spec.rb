# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe "layouts/_flash", type: :view do
  def html(level)
    render partial: "layouts/flash", locals: {level: level}
    Capybara.string(rendered)
  end

  it "shows info in blue right after notice" do
    flash[:notice] = "Gespeichert"
    flash[:info] = "Unverändert"

    page = html(:notice)

    expect(page.all(".alert").map { |alert| [alert[:class][/alert-(success|info)/, 1], alert.text.strip] })
      .to eq([%w[success Gespeichert], %w[info Unverändert]])
  end

  it "shows info only with notice" do
    flash[:info] = "Unverändert"

    expect(html(:warning)).to have_no_css(".alert")
  end

  it "keeps a list below its heading in a div" do
    flash[:warning] = "Nicht gespeichert:<ul><li>A <code>a.pdf</code></li></ul>"

    page = html(:warning)

    expect(page).to have_css(".alert-warning > div > ul > li > code", text: "a.pdf")
    expect(page).to have_no_css("p")
  end

  # As the core's: simple_format sanitizes -- scripts and event handlers go,
  # tags like img stay. Text from users must come escaped.
  it "drops scripts and event handlers, keeps safe tags" do
    flash[:warning] = "<script>alert(1)</script><img src=\"x\" onerror=\"alert(1)\">"

    expect(rendered_html = html(:warning).native.to_html).not_to include("<script", "onerror")
    expect(rendered_html).to include("<img")
  end

  it "puts each paragraph into a div" do
    flash[:alert] = "Erster Absatz\n\nZweiter Absatz\nmit Umbruch"

    page = html(:alert)

    expect(page.all(".alert-danger > div").map { |div| div.text.strip }).to eq(["Erster Absatz", "Zweiter Absatz\nmit Umbruch"])
    expect(page).to have_css(".alert-danger > div br")
    expect(page).to have_no_css("p")
  end
end
