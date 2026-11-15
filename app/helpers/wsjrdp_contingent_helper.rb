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

  # The people themselves -- the people list and the role differences on the
  # Übersicht, the matrix's links into that list, the IST tab -- only for
  # whoever may see the contingent's people in full, across all its groups;
  # not e.g. an eHoC, who sees the figures only.
  def contingent_people_visible? = can?(:index_deep_full_people, Group.root)

  # A person's name as a chip, with mini tags behind it
  #
  # counted_in: the team a person was already counted in.
  # guest: a guest of the team
  def person_chip(person, counted_in: nil, guest: false)
    content_parts = [contingent_person_link(person.nickname_or_short_first_name, person, class: "p-chip-name"), *person_mini_tags(person)]
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

  # A person's name as a link to the person's page -- or as plain text where
  # the viewer may not open that page (e.g. an eHoC, who sees the contingent
  # pages but not the people).
  def contingent_person_link(text, person, **options)
    return link_to(text, person_path(person.id), **options) if contingent_person_visible?(person)

    content_tag(:span, text, **options.except(:data))
  end

  def contingent_person_visible?(person) = contingent_visible_person_ids.include?(person.id)

  # The people the viewer may see, in one query for the whole page: the rule
  # of the core's person search (PersonReadables), the same as :show.
  def contingent_visible_person_ids
    @contingent_visible_person_ids ||= Person.accessible_by(PersonReadables.new(current_user)).pluck(:id).to_set
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
    prefix = content_tag(:span, [role, person.id].compact.join(" "), class: "text-muted fw-light")
    name = contingent_person_link(full_name, person, class: "co-person-name", title: full_name,
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
  # names it when they do not go together. The role stands before the
  # person's id only while the column Rolle is hidden.
  def contingent_people_table_columns
    contingent_people_columns(people_table_state, contingent_page_people, role_prefix: :unless_role_column)
  end

  # The same columns for the people of one unit on Kontingent > Units
  # (Contingent::WsjrdpUnitsController), the unit's people table. Whoever
  # counts for the unit only as the unit they were in last (leaving, e.g. on
  # a waiting list now) has both behind the name: "zuletzt <unit>, jetzt
  # <group>", the group linked. The role stands before the person's id only
  # while the column Rolle is hidden.
  def contingent_unit_people_table_columns
    contingent_people_columns(unit_people_table_state, unit_people,
      columns: Wsjrdp2027::ContingentUnits::PEOPLE_COLUMNS, role_prefix: :unless_role_column,
      extra_cells: {"cancel" => ->(entry) { contingent_cancel_icon(entry) },
                    "confirmed_at" => ->(entry) { contingent_day(entry.contract_confirmed_at) },
                    "joined" => ->(entry) { unit.gone?(entry) ? "" : contingent_day(unit.joined[entry.id]) },
                    "patrol" => ->(entry) { unit.gone?(entry) ? "" : contingent_patrol_cell(entry) },
                    "role" => ->(entry) { contingent_unit_role_cell(unit, entry) },
                    "budget" => ->(entry) {
                      contingent_budget_cell(entry, unit_people[entry.id], moved: unit.moved?(entry))
                    }},
      person_suffix: ->(entry) {
        now = contingent_group_link(entry)
        if unit.moved?(entry)
          left = unit.left_on[entry.id]
          partner = unit.swapped_with[entry.id]
          words = [(partner ? "getauscht mit ##{partner.id}" : "gewechselt"),
            ("bis #{contingent_day(left)} hier" if left)].compact.join(", ")
          icon = contingent_movement_icon(partner ? :swapped : :moved)
          content_tag(:span, safe_join([icon, " #{words}, jetzt ", now]), class: "text-muted fw-light small")
        elsif unit.former?(entry)
          icon = contingent_movement_icon(Wsjrdp2027::ContingentUnits.cancelling?(entry) ? :cancelling : :deregistered)
          content_tag(:span, safe_join([icon, " zuletzt #{unit.name}, jetzt ", now]), class: "text-muted fw-light small")
        end
      })
  end

  # What a person means for the budget (Wsjrdp2027::ContingentUnits.budget_parts),
  # a line each:
  # - deregistered: + the Einbehalt (the compensation entered on the Abmeldung
  #   page, else the one of the T&R)
  # - in Abmeldung: the same, grey -- not counted while the deregistration runs
  # - a fee reduction, unless it comes from the JSF (its hint): − the reduction
  # `person`: the person in full (nil: nothing to show). Whoever moved to
  # another group counts there, so shows nothing here (`moved`).
  def contingent_budget_cell(entry, person, moved: false)
    return "" if person.nil? || moved

    parts = Wsjrdp2027::ContingentUnits.budget_parts(entry, person)
    lines = []
    if parts[:pending].positive?
      lines << content_tag(:div, "+#{fin_money(parts[:pending] / 100.0)}", class: "text-muted fw-light",
        title: "Einbehalt bei Abmeldung – noch nicht gezählt, die Abmeldung läuft noch")
    elsif parts[:einbehalt].positive?
      lines << content_tag(:div, "+#{fin_money(parts[:einbehalt] / 100.0)}", title: "Einbehalt bei Abmeldung")
    end
    if parts[:reduction].positive?
      title = ["Beitragsreduktion", person.wsjrdp_total_fee_reduction_hint.presence].compact.join(": ")
      lines << content_tag(:div, "−#{fin_money(parts[:reduction] / 100.0)}", title: title)
    end
    safe_join(lines)
  end

  # A unit's budget (Unit#budget_cents): the sum of its people's, signed;
  # below it, small and grey, the sum with the Einbehalt of those in
  # Abmeldung -- where there are any.
  # Nothing at all where both are 0.
  def contingent_unit_budget(counted_cents, pending_cents)
    return "" if counted_cents.zero? && pending_cents.zero?

    sum = content_tag(:span, contingent_signed_money(counted_cents), class: "co-budget")
    return sum unless pending_cents.positive?

    with = content_tag(:span, contingent_signed_money(counted_cents + pending_cents), class: "co-budget-pending",
      title: "mit dem Einbehalt der Personen in Abmeldung (+#{fin_money(pending_cents / 100.0)})")
    safe_join([sum, with])
  end

  # "+1.700,00 €", "−55,00 €", "0,00 €".
  def contingent_signed_money(cents)
    sign = if cents.positive?
      "+"
    elsif cents.negative?
      "−"
    else
      ""
    end
    "#{sign}#{fin_money(cents.abs / 100.0)}"
  end

  # The role in a unit's people table; muted and struck through for whoever
  # no longer belongs to the unit (moved elsewhere or deregistered).
  def contingent_unit_role_cell(unit, entry)
    role = entry.role_difference || entry.wsjrdp_role
    return role unless unit.gone?(entry)

    content_tag(:span, role, class: "text-muted text-decoration-line-through", title: "nicht mehr in der Unit")
  end

  # A day as the lists write it (dd.mm.yyyy), nothing for none.
  def contingent_day(value) = value ? l(value.to_date, format: "%d.%m.%Y") : ""

  # In Abmeldung (status deregistration_noted): the hourglass of the movements
  # (MOVEMENT_ICONS), and behind it the link to each helpdesk ticket of the
  # deregistration (#contingent_ticket_links); nothing for anybody else.
  def contingent_cancel_icon(entry)
    return "" unless Wsjrdp2027::ContingentUnits.cancelling?(entry)

    icon = content_tag(:span, contingent_movement_icon(:cancelling), class: "co-cancel-icon",
      title: "in Abmeldung", "aria-label": "in Abmeldung")
    tickets = contingent_ticket_links(entry, :deregistration_issue)
    return icon if tickets.empty?

    safe_join([icon, content_tag(:span, safe_join(tickets, ", "), class: "co-cancel-ticket small")], " ")
  end

  # The group a person is in now, linked to its page: by its group code,
  # else its short name, else its name (the root group: "CMT").
  def contingent_group_link(entry)
    link_to(contingent_group_label(entry), group_path(entry.group_id), data: {turbo_frame: "_top"},
      title: entry.group_name)
  end

  def contingent_group_label(entry) = contingent_group_labels.fetch(entry.group_id, entry.group_name)

  def contingent_group_labels
    @contingent_group_labels ||= Group.unscoped.pluck(:id, :name, :short_name, :additional_info)
      .to_h { |id, name, short_name, info| [id, (info || {})["group_code"].presence || short_name.presence || name] }
  end

  # A link per helpdesk ticket key in the person's `field`
  # (Wsjrdp2027::ContingentUnits::TICKET_KEY), each opening the ticket in a
  # new tab.
  def contingent_ticket_links(entry, field)
    entry.public_send(field).to_s.scan(Wsjrdp2027::ContingentUnits::TICKET_KEY).uniq.map do |key|
      link_to(key, "https://helpdesk.worldscoutjamboree.de/browse/#{key}", target: "_blank", rel: "noopener",
        title: "Helpdesk-Ticket von #{entry.name}")
    end
  end

  # The people columns with their cells, for a table's state and its shown
  # people in full by id.
  # `role_prefix`: whether the person's role stands before the id -- true, or
  # :unless_role_column (only while the column Rolle is hidden).
  def contingent_people_columns(state, page_people, columns: Wsjrdp2027::ContingentPeopleColumns::COLUMNS,
    extra_cells: {}, person_suffix: nil, role_prefix: true)
    visible = state.visible_column_keys
    role_prefix = visible.exclude?("role") if role_prefix == :unless_role_column
    cells = {
      "person" => ->(entry) {
        person = page_people[entry.id]
        label = person ? contingent_person_label(person, role: (entry.wsjrdp_role if role_prefix)) : entry.name
        suffix = person_suffix&.call(entry)
        suffix ? safe_join([label, suffix], " ") : label
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
    }.merge(extra_cells)
    columns.map { |col| col.to_table_column(cell: cells.fetch(col.key)) }
  end

  def contingent_page_people
    @contingent_page_people ||= Person.where(id: people_rows.page.map(&:id)).includes(:tags, :primary_group)
      .index_by(&:id)
  end

  # The columns of the unit list on Kontingent > Units
  # (Wsjrdp2027::ContingentUnitsColumns) with their cells, those of the
  # chosen view (VIEW_COLUMNS) only. The name links the unit's group page; a
  # click on the rest of the row opens its people.
  def contingent_units_table_columns(view)
    cells = {
      "name" => ->(unit) { link_to(unit.name, group_path(unit.id), data: {turbo_frame: "_top"}) },
      "without_patrol" => ->(unit) { contingent_without_patrol(unit) },
      "confirmed" => ->(unit) { unit.confirmed },
      "open" => ->(unit) { unit.open },
      "in_force" => ->(unit) { unit.in_force_total },
      "left" => ->(unit) { contingent_movement_lines(unit, unit.left_movements) },
      "swapped" => ->(unit) { contingent_movement_lines(unit, unit.swap_movements) },
      "arrived" => ->(unit) { contingent_movement_lines(unit, unit.arrival_movements) },
      "movements" => ->(unit) { contingent_movement_lines(unit, unit.movements_by_day) },
      "balance" => ->(unit) { contingent_unit_balance(unit) },
      "budget" => ->(unit) { contingent_unit_budget(unit.budget_cents, unit.budget_pending_cents) }
    }
    hidden = Wsjrdp2027::ContingentUnitsColumns.hidden_in(view)
    Wsjrdp2027::ContingentUnitsColumns::COLUMNS.reject { |col| hidden.include?(col.key) }
      .map { |col| col.to_table_column(cell: cells.fetch(col.key)) }
  end

  # The people in force without a patrol: 0 grey, red where nobody in the
  # unit has one yet, orange where only some lack one.
  def contingent_without_patrol(unit)
    return content_tag(:span, 0, class: "text-muted") if unit.without_patrol.zero?

    css, title = unit.patrols_unset? ? ["co-patrol-unset", "noch niemand in einer Patrol"] :
      ["co-patrol-partly", "ein Teil noch ohne Patrol"]
    content_tag(:span, unit.without_patrol, class: css, title: title)
  end

  # The sum row of the unit list: every figure over all units shown -- but
  # Haushalt, whose sum over units means nothing.
  def contingent_units_table_footer(col, units)
    case col[:key]
    when "name" then content_tag(:span, "Σ", title: "Summe", "aria-label": "Summe")
    when "without_patrol" then units.sum(&:without_patrol)
    when "confirmed" then units.sum(&:confirmed)
    when "open" then units.sum(&:open)
    when "in_force" then units.sum(&:in_force_total)
    when "left" then units.sum { |u| u.left_movements.size }
    when "swapped" then units.sum { |u| u.swap_movements.size }
    when "arrived" then units.sum { |u| u.arrival_movements.size }
    when "movements" then units.sum { |u| u.movements.size }
    when "balance" then contingent_balance_sum(units.sum(&:formed_count), units.sum(&:left_count),
      units.sum(&:arrived_count), units.sum(&:now_count))
    end
  end

  # The icon of each kind of movement (Wsjrdp2027::ContingentUnits::Movement),
  # its colour class and its word -- the legend above the table says the
  # same. The newcomer's arrow is the door icon mirrored: an arrow pointing
  # left into a bar, the counterpart of leaving through the door.
  MOVEMENT_ICONS = {
    arrived: {icon: :"sign-in-alt", flip: true, css: "co-move-in", word: "nachgerückt"},
    deregistered: {icon: :"sign-out-alt", css: "co-move-out", word: "abgemeldet"},
    cancelling: {icon: :"hourglass-half", css: "co-move-wait", word: "in Abmeldung"},
    swapped: {icon: :"exchange-alt", css: "co-move-swap", word: "getauscht"},
    moved: {icon: :"long-arrow-alt-right", css: "co-move-moved", word: "gewechselt"}
  }.freeze

  def contingent_movement_icon(kind)
    info = MOVEMENT_ICONS.fetch(kind)
    icon(info[:icon], class: ["co-move-icon", info[:css], ("fa-flip-horizontal" if info[:flip])].compact.join(" "),
      "aria-hidden": true)
  end

  # The legend of the movement icons, above the table.
  def contingent_movement_legend
    items = MOVEMENT_ICONS.map do |kind, info|
      content_tag(:span, safe_join([contingent_movement_icon(kind), info[:word]], " "), class: "co-move-legend-item")
    end
    content_tag(:div, safe_join(items), class: "co-move-legend small")
  end

  # The movements of a cell, one line each and the same in both views: the
  # day (dd.mm.yy, in one width, so the days align), the icon, the person
  # ("#<id>"), then the partner of a swap, where to or from, the helpdesk
  # ticket -- the words in the line's graphical tooltip.
  def contingent_movement_lines(unit, movements)
    safe_join(movements.map { |movement| contingent_movement_line(unit, movement) })
  end

  def contingent_movement_line(unit, movement)
    entry = movement.entry
    day = content_tag(:span, movement.on ? l(movement.on, format: "%d.%m.%y") : "…", class: "co-move-day")
    person = contingent_person_link("##{entry.id}", entry, data: {turbo_frame: "_top"})
    group = contingent_group_id_link(movement.group_id) if movement.group_id
    if movement.partner
      partner_link = contingent_person_link("##{movement.partner.id}", movement.partner, data: {turbo_frame: "_top"})
      partner = content_tag(:span, safe_join([content_tag(:span, "mit", class: "text-muted"), partner_link], " "))
    end
    ticket_field = (movement.kind == :arrived) ? :late_confirmation_issue : :deregistration_issue
    tickets = contingent_ticket_links(entry, ticket_field)
    ticket = content_tag(:span, safe_join(["(", safe_join(tickets, ", "), ")"]), class: "co-unit-ticket") if tickets.any?
    icon = contingent_movement_icon(movement.kind)
    line = content_tag(:span, safe_join([day, icon, person, partner, group, ticket].compact, " "), class: "co-move")
    content_tag(:div, wsjrdp_tip(line, lines: contingent_movement_tip(unit, movement)), class: "co-move-line")
  end

  def contingent_movement_tip(unit, movement)
    entry = movement.entry
    word = MOVEMENT_ICONS.fetch(movement.kind)[:word]
    when_words = movement.on ? l(movement.on, format: "%d.%m.%Y") : "Tag unbekannt"
    lines = [[word, when_words], ["Person", "#{entry.name} (##{entry.id})"]]
    lines << ["mit", "#{movement.partner.name} (##{movement.partner.id})"] if movement.partner
    case movement.kind
    when :arrived then lines << ["aus", contingent_group_labels.fetch(movement.group_id, "–")] if movement.group_id
    when :moved, :swapped then lines << ["nach", contingent_group_labels.fetch(movement.group_id, "–")]
    end
    if movement.kind == :cancelling && movement.present
      lines << [nil, "noch in der Unit, aber schon abgezogen"]
    end
    lines << [nil, "nicht in der Bilanz (Tausch)"] if movement.kind == :swapped
    field = (movement.kind == :arrived) ? :late_confirmation_issue : :deregistration_issue
    ticket = entry.public_send(field)
    lines << ["Ticket", ticket] if ticket.present?
    lines
  end

  # The balance of a unit: eingeteilt − verlassen + nachgerückt = jetzt,
  # marked where it does not add up (roles that do not fit together); "jetzt"
  # leaves out who is in Abmeldung (counted in verlassen), the second line
  # says how many they are.
  def contingent_unit_balance(unit)
    sum = contingent_balance_sum(unit.formed_count, unit.left_count, unit.arrived_count, unit.now_count)
    open = unit.open_cancelling
    note = content_tag(:span, "#{open} in Abm.", class: "co-balance-pending") if open.positive?
    safe_join([sum, note].compact)
  end

  # Without movements the number alone ("40", not "40 = 40").
  def contingent_balance_sum(formed, left, arrived, now)
    return content_tag(:span, now, class: "co-balance") if left.zero? && arrived.zero? && formed == now

    parts = [formed.to_s]
    parts << content_tag(:span, "−#{left}", class: "co-balance-minus") if left.positive?
    parts << content_tag(:span, "+#{arrived}", class: "co-balance-plus") if arrived.positive?
    expected = formed - left + arrived
    result = if expected == now
      "= #{now}"
    else
      content_tag(:span, "= #{expected} ≠ #{now}", class: "co-balance-bad",
        title: "Die Bewegungen ergeben #{expected}, in der Unit sind #{now} – Rollen passen nicht zusammen")
    end
    content_tag(:span, safe_join([*parts, result], " "), class: "co-balance")
  end

  # A group by id, linked, by its group code, else short name, else name --
  # a waiting list short ("YP Warteliste" → "YP WL"), so a movement's line
  # stays short; the full name is the link's tooltip.
  def contingent_group_id_link(group_id)
    label = contingent_group_labels.fetch(group_id, "?")
    link_to(label.sub(/\s*Warteliste\z/i, " WL"), group_path(group_id), data: {turbo_frame: "_top"}, title: label)
  end

  # counted_in: person id => the team that person was already counted in.
  def people_chips(people, counted_in: {}, guest: false)
    safe_join(people.map { |p| person_chip(p, counted_in: counted_in[p.id], guest: guest) }, " ")
  end

  # The patrol letter, "nicht gesetzt" (muted) for an UL or YP not in a patrol yet,
  # nothing for everybody else.
  def contingent_patrol_cell(entry)
    case entry.patrol
    when nil then ""
    when "none" then content_tag(:span, "nicht gesetzt", class: "text-muted")
    else entry.patrol.split("-").last
    end
  end
end
