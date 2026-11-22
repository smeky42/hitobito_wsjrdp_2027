# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# What the Moss users, teams and departments pages share: status and role
# labels, links to a linked Moss record (which may dangle), Moss ids with their
# copy icon. Links leave the detail's frame (data-turbo-frame _top).
module Fin::MossOrganisationHelper
  def moss_org_status_label(status)
    return nil if status.blank?

    Fin::MossOrganisationFilter.status_label(status)
  end

  # The label; for the write tier also the stored value, as Moss sends it.
  def moss_org_status_with_raw(record)
    label = moss_org_status_label(record.status)
    return label if label.nil? || !can?(:update, record)

    safe_join([label, " ", content_tag(:span, record.status, class: "text-muted fw-light ms-1")])
  end

  def moss_org_role_label(role) = t("fin.moss_organisation.roles.#{role}", default: role.to_s)

  # The roles in German; the role Moss sends for one it has no name for yet
  # stays in the background.
  def moss_org_roles(user)
    labels = user.roles.map do |role|
      label = moss_org_role_label(role)
      (role == "UNKNOWN_DEFAULT_OPEN_API") ? content_tag(:span, label, class: "text-muted fw-light") : label
    end
    labels.empty? ? nil : safe_join(labels, ", ")
  end

  # A Moss user in a detail (manager, team lead, owner): card icon and user,
  # then person icon and the linked person, if any.
  def moss_org_user_reference(user, uuid)
    return moss_org_reference(nil, uuid) unless user

    parts = [moss_org_kind_icon(:moss_user), moss_org_link_with_newtab(user.to_s, moss_user_path(user))]
    if user.person
      parts << content_tag(:span, moss_org_person_with_icon(user.person), class: "ms-3 d-inline-block")
    end
    safe_join(parts)
  end

  # The same in a list cell: the icons first (a cut-off name never hides
  # them), the person icon alone linking the person.
  def moss_org_user_cell(user)
    return nil unless user

    parts = [moss_org_kind_icon(:moss_user)]
    person = user.person
    if person && assoc_link?(person)
      parts << link_to(icon(:user), person_path(person), class: "text-muted me-1", data: {turbo_frame: "_top"},
        title: "Hitobito-Person: #{person}", "aria-label": "Hitobito-Person: #{person}")
    end
    parts << moss_org_link(user.to_s, moss_user_path(user))
    safe_join(parts)
  end

  # A Hitobito person in a list cell: its icon and its link.
  def moss_org_person_cell(person) = person && safe_join([moss_org_kind_icon(:person), moss_org_person(person)])

  # A Hitobito person with its icon, its link and the new-tab icon.
  def moss_org_person_with_icon(person)
    link = moss_org_person(person)
    link = safe_join([link, wsjrdp_newtab_link(person_path(person))]) if assoc_link?(person)
    safe_join([moss_org_kind_icon(:person), link])
  end

  MOSS_ORG_KIND_ICONS = {
    moss_user: ["credit-card", "Moss-Benutzer"],
    person: ["user", "Hitobito-Person"]
  }.freeze

  def moss_org_kind_icon(kind)
    name, title = MOSS_ORG_KIND_ICONS.fetch(kind)
    icon(name, class: "text-muted me-1", title: title, "aria-label": title, role: "img")
  end

  # The same link with the icon that opens it in a new tab, for a detail.
  def moss_org_link_with_newtab(label, path) = safe_join([moss_org_link(label, path), wsjrdp_newtab_link(path)])

  # A link that leaves the detail's frame.
  def moss_org_link(label, path)
    link_to(label, path, data: {turbo_frame: "_top"})
  end

  # The linked Moss record, or a muted note when Hitobito does not have it.
  def moss_org_reference(record, uuid)
    return moss_org_link_with_newtab(record.to_s, polymorphic_path(record)) if record
    return nil if uuid.blank?

    content_tag(:span, "nicht in Hitobito", class: "text-muted small")
  end

  # A Moss id, muted, with the icon that copies it.
  def moss_org_uuid(uuid)
    return nil if uuid.blank?

    fin_account_copyable(content_tag(:span, uuid, class: "text-muted font-monospace small"), uuid)
  end

  # A Hitobito person, linked the way hitobito does (FormatHelper#assoc_link).
  def moss_org_person(person)
    return nil unless person

    link_to_if(assoc_link?(person), person.to_s, person, data: {turbo_frame: "_top"})
  end

  # The name cell of a list: the record's page, and a badge once Moss no
  # longer returns it.
  def moss_org_name_cell(record, label = record.to_s)
    badge = content_tag(:span, "entfernt", class: "badge text-bg-secondary ms-1") if record.removed_from_moss?
    safe_join([moss_org_link(label, polymorphic_path(record)), badge].compact)
  end

  def moss_org_row_class(record) = ("text-muted" if record.removed_from_moss?)

  def moss_org_dash = content_tag(:span, "—", class: "text-muted")
end
