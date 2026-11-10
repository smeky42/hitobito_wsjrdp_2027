# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module WsjrdpContingentHelper
  # The chip class of a contract that is not in force
  CONTRACT_CHIP_CLASSES = {
    "none" => "p-chip-contract-none",
    "replacement_pending" => "p-chip-contract-pending",
    "ended" => "p-chip-contract-ended"
  }.freeze

  # A person's name as a chip, with mini tags behind it
  #
  # counted_in: the team a person was already counted in.
  # guest: a guest of the team
  def person_chip(person, counted_in: nil, guest: false)
    content_parts = [
      link_to(person.nickname_or_short_first_name, person_path(person.id))
    ]
    content_parts << content_tag(:span, "HA", class: "tag-ha", title: "Hauptamt") if person.paid_staff?
    if person.hoc?
      content_parts << content_tag(:span, "HoC", class: "tag-hoc")
    elsif person.ehoc?
      content_parts << content_tag(:span, "eHoC", class: "tag-ehoc")
    end
    content_parts << content_tag(:span, "JPT", class: "tag-jpt") if person.wsj_role == "JPT"
    content_parts << content_tag(:span, "EXT", class: "tag-ext") if person.wsj_role == "EXT"
    contract_class = CONTRACT_CHIP_CLASSES[person.contract_status]
    contract_muted = ("p-chip-contract-muted" if contract_class && person.wsj_role == "EXT")
    css = ["p-chip", ("p-chip-counted" if counted_in), ("p-chip-guest" if guest), contract_class, contract_muted]
      .compact.join(" ")
    titles = [
      ("schon gezählt bei #{counted_in}" if counted_in),
      ("Vertrag: #{Settings.contract_status[person.contract_status]}" if contract_class)
    ]
    content_tag(:span, safe_join(content_parts, " "), class: css, title: titles.compact.join(" · ").presence)
  end

  # counted_in: person id => the team that person was already counted in.
  def people_chips(people, counted_in: {}, guest: false)
    safe_join(people.map { |p| person_chip(p, counted_in: counted_in[p.id], guest: guest) }, " ")
  end
end
