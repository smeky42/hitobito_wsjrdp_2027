# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# A sheet title with markup for the page's h1. The object IS the plain text --
# what the browser tab, a breadcrumb or any other reader of the title gets --
# and carries the html_safe markup beside it, which only the h1 asks for:
# Wsjrdp2027::SheetHelper#title answers #html inside the sheet's body (where
# the core layout puts `%h1= title`) and the plain text everywhere else (the
# `<title>` in the head).
class Wsjrdp::SheetTitle < String
  attr_reader :html

  def initialize(plain, html)
    super(plain)
    @html = html
  end

  def plain = String.new(self)
end
