# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"
require "typst"

# The letter template itself, with the options no document of ours uses yet: a
# window address field and the two footers. Compiled from a body written here,
# in a temporary project of its own -- the wagon's typst directory holds the
# documents we ship, not probes.
describe "wsjrdp2027.typ" do
  # What the letter needs around the body it is given.
  def dependencies
    dir = Wsjrdp2027::TypstDocument.typst_dir
    {
      "wsjrdp2027.typ" => File.read(dir.join("wsjrdp2027.typ")),
      "WSJ_Brief_Hintergrund.pdf" => File.binread(dir.join("WSJ_Brief_Hintergrund.pdf"))
    }
  end

  def fonts
    dir = Wsjrdp2027::TypstDocument.fonts_dir
    %w[Montserrat-Regular.ttf Montserrat-SemiBold.ttf].to_h do |name|
      [name, File.binread(dir.join(name))]
    end
  end

  def compile(options)
    source = <<~TYPST
      #import "wsjrdp2027.typ": *

      #show: wsjrdp2027_letter.with(#{options})

      Ein Brief, wie er gedruckt wird.

      #v(1em)

      Mit freundlichen Grüßen
    TYPST
    Typst::Base.from_s(source, format: :pdf, dependencies: dependencies, fonts: fonts)
      .compiled.pages.first
  end

  it "compiles a plain letter" do
    expect(compile(%(title-text: "Ein Brief"))).to start_with("%PDF")
  end

  # The return address of the field: the rdp's own two lines unless the caller
  # says otherwise, one line where a string is passed, none for "".
  def window_letter(window)
    compile(%(title-text: "Ein Brief", window-address: (#{window})))
  end

  it "compiles a window address with the default return address" do
    expect(window_letter(%(lines: ("Vorname Nachname", "Musterweg 1", "12345 Musterstadt"))))
      .to start_with("%PDF")
  end

  it "compiles a window address with a return line of its own" do
    window = <<~WINDOW
      lines: ("Vorname Nachname", "Musterweg 1", "12345 Musterstadt"),
      return-line: "Eigener Absender · Musterweg 9 · 12345 Musterstadt",
    WINDOW

    expect(window_letter(window)).to start_with("%PDF")
  end

  it "compiles a window address without a return address" do
    window = <<~WINDOW
      lines: ("Vorname Nachname", "Musterweg 1", "12345 Musterstadt"),
      return-line: "",
    WINDOW

    expect(window_letter(window)).to start_with("%PDF")
  end

  it "compiles a window address whose return line is too long to fit" do
    window = <<~WINDOW
      lines: ("Vorname Nachname", "Musterweg 1", "12345 Musterstadt"),
      return-line: "#{"Ein sehr langer Absender " * 8}",
    WINDOW

    expect(window_letter(window)).to start_with("%PDF")
  end

  it "compiles a letter with both footers" do
    options = %(title-text: "Ein Brief", role-id-name: "YP 1", footer-text: [Brief], contact-footer: true)

    expect(compile(options)).to start_with("%PDF")
  end

  it "compiles a letter with the contact footer alone" do
    options = %(title-text: "Ein Brief", contact-footer: true, classic-footer: false)

    expect(compile(options)).to start_with("%PDF")
  end

  # The default is what the documents of the scripts repository rely on: the
  # classic footer, no contact block, no address field.
  it "keeps the old shape as the default" do
    expect(compile(%(title-text: "Ein Brief", role-id-name: "YP 1"))).to start_with("%PDF")
  end
end
