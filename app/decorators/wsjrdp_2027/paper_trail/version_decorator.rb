# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027::PaperTrail::VersionDecorator
  def t_event(user: nil, item: nil, object_changes: nil, object_name: nil)
    if %w[wsjrdp_add_tag wsjrdp_remove_tag].include?(event) && object_changes.present?
      tag_change = YAML.load(object_changes, permitted_classes: [Date, Time, Symbol])["tag"] || [nil, nil]
      tag_name = ERB::Util.html_escape(tag_change&.[]((event == "wsjrdp_add_tag") ? 1 : 0))
      I18n.t(
        "version.#{event}",
        user: user,
        item: item,
        object_name: object_name,
        object_changes: object_changes,
        tag_name: tag_name
      ).html_safe
    else
      I18n.t(
        "version.#{event}",
        user: user,
        item: item,
        object_name: object_name,
        object_changes: object_changes
      )
    end
  end

  private

  # Two jsonb store keys hold a collection the core would render with #to_s:
  # additional_info["finance_group_ids"] on a person is a Hash of group id =>
  # tokens (doc/roles.md -> "Finance on a group's page"),
  # additional_info["cost_center_numbers"] on a group an Array of cost-center
  # numbers. Both are rendered per element instead.
  def attribute_change(attr, from, to)
    case attr.to_s
    when "finance_group_ids" then finance_group_ids_change(from, to)
    when "cost_center_numbers" then cost_center_numbers_change(from, to)
    else super
    end
  end

  # One line per number added and one per number removed, the removals first
  # and each group by number. A change that leaves the SET alone (a reordering)
  # has no line at all.
  def cost_center_numbers_change(from, to)
    old_numbers = cost_center_numbers(from)
    new_numbers = cost_center_numbers(to)

    lines = (old_numbers - new_numbers).sort.map { |number| cost_center_numbers_line("removed", number) } +
      (new_numbers - old_numbers).sort.map { |number| cost_center_numbers_line("added", number) }

    h.safe_join(lines, h.tag.br)
  end

  # The stored value as an Array of numbers; nil (the key added or removed)
  # works like an empty list.
  def cost_center_numbers(value) = Array(value).map(&:to_s)

  def cost_center_numbers_line(key, number)
    I18n.t("version.cost_center_numbers.#{key}",
      cost_center: ERB::Util.html_escape(cost_center_label(number))).html_safe
  end

  # The cost center the number names; a number without a master record is shown
  # as it is.
  def cost_center_label(number)
    WsjrdpCostCenter.find_by(number: number)&.to_s || number
  end

  def finance_group_ids_change(from, to)
    old_tokens = finance_group_ids_tokens(from)
    new_tokens = finance_group_ids_tokens(to)

    lines = (old_tokens.keys | new_tokens.keys)
      .reject { |id| old_tokens.fetch(id, []) == new_tokens.fetch(id, []) }
      .map { |id| [finance_group_name(id), id, old_tokens.fetch(id, []), new_tokens.fetch(id, [])] }
      .sort_by { |name, id, _old, _new| [name, id] }
      .map { |name, _id, old, new| finance_group_ids_line(name, old, new) }
      .compact_blank

    h.safe_join(lines, h.tag.br)
  end

  # The stored value as {group id => tokens}; anything but a Hash counts as no
  # entries, so a nil side (the key added or removed) works like an empty one.
  def finance_group_ids_tokens(value)
    return {} unless value.is_a?(Hash)

    value.to_h { |id, tokens| [id.to_s, Person.finance_group_tokens(tokens)] }
  end

  def finance_group_ids_line(name, old_tokens, new_tokens)
    from = finance_group_ids_token_list(old_tokens)
    to = finance_group_ids_token_list(new_tokens)
    key = attribute_change_key(from, to)
    return "" unless key

    attr = I18n.t("version.finance_group_ids.attr", group: ERB::Util.html_escape(name))
    I18n.t("version.attribute_change.#{key}", attr: attr, from: from, to: to).html_safe
  end

  def finance_group_ids_token_list(tokens)
    tokens
      .map { |token| ERB::Util.html_escape(I18n.t("version.finance_group_ids.tokens.#{token}", default: token)) }
      .join(", ")
  end

  # Group is paranoid, so a deleted group still has a name; an id that resolves
  # to nothing is shown as "#<id>".
  def finance_group_name(id)
    Group.with_deleted.find_by(id: id)&.to_s || "##{id}"
  end
end
