# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module WsjrdpContingentHelper
  def person_chip(person)
    content_parts = [
      link_to(person.nickname_or_short_first_name, person_path(person.id))
    ]
    if person.hoc?
      content_parts << content_tag(:span, "HoC", class: "tag-hoc")
    elsif person.ehoc?
      content_parts << content_tag(:span, "eHoC", class: "tag-ehoc")
    end
    content_parts << content_tag(:span, "JPT", class: "tag-jpt") if person.wsj_role == "JPT"
    content_tag(:span, content_parts.join(" ").html_safe, class: "p-chip")
  end

  def people_chips(people)
    people.map { |p| person_chip(p) }.join(" ").html_safe
  end
end
