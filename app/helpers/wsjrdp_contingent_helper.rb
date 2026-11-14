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
    content_parts = [link_to(person.nickname_or_short_first_name, person_path(person.id)), *person_mini_tags(person)]
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

  # The mini tags behind a person's name: HA (Hauptamt) first, then HoC or
  # eHoC, then the jamboree role JPT or EXT -- or, when the contingent role and
  # the jamboree role differ, a tag saying both ("CMT→JPT") in its place.
  def person_mini_tags(person)
    tags = []
    tags << content_tag(:span, "HA", class: "tag-ha", title: "Hauptamt") if person.paid_staff?
    if person.hoc?
      tags << content_tag(:span, "HoC", class: "tag-hoc")
    elsif person.ehoc?
      tags << content_tag(:span, "eHoC", class: "tag-ehoc")
    end
    if (difference = person.role_difference)
      tags << content_tag(:span, difference, class: "tag-role-diff", title: "Kontingents-Rolle → Rolle auf dem Jamboree")
    elsif %w[JPT EXT].include?(person.wsj_role)
      tags << content_tag(:span, person.wsj_role, class: "tag-#{person.wsj_role.downcase}")
    end
    tags
  end

  # A person the way the finance lists show one (Fin::PaymentDetailsHelper#payment_person):
  # role and id muted, then the name with the nickname as a link -- here with
  # the mini tags behind it.
  # Where the cell is too narrow, only the name is cut (with the full name as
  # its tooltip); prefix and mini tags stay whole (.co-person, on the overview).
  def contingent_person_label(person, role:)
    full_name = person.short_full_name_with_nickname
    prefix = content_tag(:span, "#{role} #{person.id}", class: "text-muted fw-light")
    name = link_to(full_name, person_path(person.id), class: "co-person-name", title: full_name,
      data: {turbo_frame: "_top"})
    content_tag(:span, safe_join([prefix, name, *person_mini_tags(person)], " "), class: "co-person")
  end

  # The contract's words on the overview, else those of the finance lists
  # (Fin::PersonStatusHelper::CONTRACT_WORDS): a replacement pending is
  # "neu ausstehend", none a muted dash.
  def contingent_contract_words
    @contingent_contract_words ||= Fin::PersonStatusHelper::CONTRACT_WORDS.merge(
      "replacement_pending" => "neu ausstehend", "none" => content_tag(:span, "—", class: "text-muted")
    )
  end

  # The columns of the people list on Kontingent > Übersicht
  # (Wsjrdp2027::ContingentPeopleColumns) with their cells. Name and mini tags
  # need the people in full; only the shown page loads them
  # (#contingent_page_people). Contract and status as on the finance lists
  # (Fin::PersonStatusHelper): in a word, coloured, the full label and the
  # dates as the tooltip; where one of the two columns is hidden, the other
  # names it when they do not go together.
  def contingent_people_table_columns
    visible = people_table_state.visible_column_keys
    cells = {
      "person" => ->(entry) {
        person = contingent_page_people[entry.id]
        person ? contingent_person_label(person, role: entry.wsjrdp_role) : entry.name
      },
      "contract" => ->(entry) {
        fin_person_contract(entry, status: visible.exclude?("status"), words: contingent_contract_words)
      },
      "status" => ->(entry) {
        fin_person_status(entry, contract: visible.exclude?("contract"), contract_words: contingent_contract_words)
      },
      "reason" => ->(entry) { content_tag(:span, entry.reason, class: "co-reason-#{entry.state}", title: entry.reason) },
      "group" => ->(entry) { content_tag(:span, entry.group_name, class: ("text-muted" unless entry.wsjrdp)) },
      "role" => ->(entry) { entry.role_difference || entry.wsjrdp_role },
      "patrol" => ->(entry) { contingent_patrol_cell(entry) }
    }
    Wsjrdp2027::ContingentPeopleColumns::COLUMNS.map { |col| col.to_table_column(cell: cells.fetch(col.key)) }
  end

  def contingent_page_people
    @contingent_page_people ||= Person.where(id: people_rows.page.map(&:id)).includes(:tags, :primary_group)
      .index_by(&:id)
  end

  # counted_in: person id => the team that person was already counted in.
  def people_chips(people, counted_in: {}, guest: false)
    safe_join(people.map { |p| person_chip(p, counted_in: counted_in[p.id], guest: guest) }, " ")
  end

  # The patrol letter, "keine" (muted) for an UL or YP of a unit without one,
  # nothing for everybody else.
  def contingent_patrol_cell(entry)
    case entry.patrol
    when nil then ""
    when "none" then content_tag(:span, "keine", class: "text-muted")
    else entry.patrol.split("-").last
    end
  end
end
