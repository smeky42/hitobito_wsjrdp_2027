# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027::PaperTrail::VersionDecorator
  # A log entry of the wagon (Wsjrdp::LogEvents) is shown by its own rules,
  # also when its item is not its main (where the core would show an
  # association change), and never fails the log page.
  def changes
    return super unless Wsjrdp::LogEvents.wsjrdp?(event)

    content_tag(:div, wsjrdp_event_text)
  end

  private

  # What a value of a log entry shows when it is missing or empty.
  WSJRDP_MISSING_VALUE = "–"

  # The sentence of the event with its params, then a line per detail; for an
  # event the register does not know, or whose sentence cannot be made, the
  # generic line and every key with its value.
  def wsjrdp_event_text
    data = Wsjrdp::LogEvents.data(model)
    definition = Wsjrdp::LogEvents.definition(event)
    return wsjrdp_generic_text(data) unless definition

    begin
      wsjrdp_sentence(definition, data)
    rescue I18n::ArgumentError
      wsjrdp_generic_text(data)
    end
  end

  def wsjrdp_sentence(definition, data)
    params = definition.fetch(:params, {}).to_h { |key, type| [key, wsjrdp_value(type, data[key.to_s])] }
    lines = [I18n.t("version.#{event}", **params, raise: true).html_safe]
    definition.fetch(:details, {}).each do |key, type|
      next unless data.key?(key.to_s)

      label = I18n.t("version.wsjrdp_data.#{key}", default: key.to_s)
      lines << I18n.t("version.wsjrdp_detail",
        label: ERB::Util.html_escape(label), value: wsjrdp_value(type, data[key.to_s])).html_safe
    end
    h.safe_join(lines, h.tag.br)
  end

  def wsjrdp_generic_text(data)
    lines = [I18n.t("version.wsjrdp_generic", event: ERB::Util.html_escape(event)).html_safe]
    lines += data.map do |key, value|
      ERB::Util.html_escape("#{key}: #{(value.is_a?(Hash) || value.is_a?(Array)) ? value.to_json : value}")
    end
    h.safe_join(lines, h.tag.br)
  end

  # A value of a log entry by its type, escaped: :text (on one line), :date
  # (an ISO date), :cents (EUR), :person and :group (by id, "#<id>" for none),
  # :list (of texts), :note_category (its label, else as stored). A value its
  # type cannot read is shown as stored.
  def wsjrdp_value(type, value)
    return WSJRDP_MISSING_VALUE if value.nil? || value == "" || value == []

    ERB::Util.html_escape(wsjrdp_value_text(type, value))
  rescue ArgumentError, TypeError
    ERB::Util.html_escape(value.to_s.squish)
  end

  def wsjrdp_value_text(type, value)
    case type
    when :date then I18n.l(Date.iso8601(value.to_s))
    when :cents then h.format_cents_de(Integer(value))
    when :person then wsjrdp_record_label(::Person, value)
    when :group then wsjrdp_record_label(::Group.with_deleted, value)
    when :list then Array(value).map { |element| element.to_s.squish }.join(", ")
    when :note_category then wsjrdp_note_category_label(value.to_s)
    else value.to_s.squish
    end
  end

  def wsjrdp_record_label(scope, id) = scope.find_by(id: Integer(id))&.to_s || "##{id}"

  def wsjrdp_note_category_label(category)
    return category unless category.match?(/\A\w+\z/)

    I18n.t("version.wsjrdp_note_categories.#{category}", default: category)
  end

  ALLERGY_ATTRS = Wsjrdp2027::Person::JamboreeData::ALLERGIES.map { |allergy| "allergy_#{allergy}" }.freeze
  COMFORT_ATTRS = Wsjrdp2027::Person::JamboreeData::COMFORT_ATTRS.map(&:to_s).freeze

  # Every answer of the page "Daten für den Veranstalter": the keys of
  # people.jamboree_data and the person columns the page edits as well.
  JAMBOREE_PAGE_ATTRS = (Wsjrdp2027::Person::JamboreeData::ATTRS.map(&:to_s) +
    %w[shirt_size uniform_size uniform_long_sleeve uniform_order headgear diet]).freeze

  # An allergy's box is named by its allergen alone ("Milch"), which says
  # nothing in the log; there it is "Allergie Milch".
  def attribute_change_args(attr, from, to)
    args = super
    return args unless ALLERGY_ATTRS.include?(attr.to_s)

    args.merge(attr: I18n.t("people.jamboree_data.allergy_log_attr", allergy: args[:attr]))
  end

  # Three jsonb store keys hold something the core would render with #to_s:
  # additional_info["finance_group_ids"] on a person is a Hash of group id =>
  # tokens (doc/roles.md -> "Finance on a group's page"),
  # additional_info["deregistration_record"] on a person the kind of a
  # deregistration and what its documents carry
  # (Wsjrdp2027::DeregistrationRecord), and
  # additional_info["cost_center_numbers"] on a group an Array of cost-center
  # numbers. Each is rendered per element instead. The person's active
  # installment plan (wsjrdp_raw_installments_eur, an Array of decimals) is
  # written out like everywhere else (installments_text), its payment method
  # by its label, and an i18n_enum attribute by its labels. An answer of
  # "Daten für den Veranstalter" as stored, with its label (jamboree_change).
  def attribute_change(attr, from, to)
    return jamboree_change(attr, from, to) if jamboree_page_attr?(attr)

    case attr.to_s
    when "wsjrdp_raw_installments_eur" then raw_installments_eur_change(attr, from, to)
    when "wsjrdp_installments_payment_method" then payment_method_change(attr, from, to)
    when "finance_group_ids" then finance_group_ids_change(from, to)
    when Wsjrdp2027::DeregistrationRecord::KEY then deregistration_record_change(from, to)
    when "cost_center_numbers" then cost_center_numbers_change(from, to)
    else
      i18n_enum_attr?(attr) ? i18n_enum_change(attr, from, to) : super
    end
  end

  # An attribute with labels from i18n_enum (the language levels of the
  # Zusatzdaten, gender) is written out by its labels, "Grundkenntnisse"
  # rather than "basic"; a value without a label as stored.
  def i18n_enum_attr?(attr) = item_class.respond_to?(:"#{attr}_labels")

  def jamboree_page_attr?(attr) = item_class <= ::Person && JAMBOREE_PAGE_ATTRS.include?(attr.to_s)

  # The value as stored and, where it differs, its label in brackets:
  # "severe [Schwere anaphylaktische Reaktion (lebensbedrohlich)]",
  # "true [Langarm]", "false [unwohl]", "2027-07-30 [30.07.2027]"; a free text
  # as it is, and a value labelled just Ja or Nein ("true", "no") too.
  def jamboree_change(attr, from, to)
    from = jamboree_value_text(attr, from)
    to = jamboree_value_text(attr, to)
    key = attribute_change_key(from, to)
    return "" unless key

    I18n.t("version.attribute_change.#{key}",
      **attribute_change_args(attr, nil, nil),
      from: ERB::Util.html_escape(from), to: ERB::Util.html_escape(to)).html_safe
  end

  def jamboree_value_text(attr, value)
    return nil if value.nil? || value == "" || value == []

    stored = value.is_a?(Array) ? value.join(", ") : value.to_s
    label = jamboree_value_label(attr.to_s, value)
    (label.blank? || label == stored || %w[ja nein].include?(label.downcase)) ? stored : "#{stored} [#{label}]"
  end

  def jamboree_value_label(attr, value) # rubocop:disable Metrics/CyclomaticComplexity
    case attr
    when "medical_equipment_needs"
      Array(value).map { |v| I18n.t("activerecord.attributes.person.jamboree_medical_equipment.#{v}", default: v) }.join(", ")
    when "uniform_long_sleeve" then I18n.t("people.additional_info_fields.#{value ? "long_sleeve" : "short_sleeve"}")
    when "uniform_order" then I18n.t("people.additional_info_fields.#{value ? "answer_yes" : "answer_no"}")
    when *COMFORT_ATTRS then I18n.t("people.jamboree_data.#{value ? "comfortable" : "uncomfortable"}")
    when "headgear" then Settings.headgear[value.to_s]
    when "diet" then Settings.diets[value.to_s]
    else
      if i18n_enum_attr?(attr) then item_class.public_send(:"#{attr}_labels")[value.to_s.to_sym]
      elsif value == true || value == false then I18n.t("global.#{value ? "yes" : "no"}")
      elsif value.respond_to?(:strftime) then I18n.l(value.to_date)
      end
    end
  end

  def i18n_enum_change(attr, from, to)
    labels = item_class.public_send(:"#{attr}_labels")
    from = labels.fetch(from.to_s.to_sym, from) if from.present?
    to = labels.fetch(to.to_s.to_sym, to) if to.present?
    key = attribute_change_key(from, to)
    return "" unless key

    I18n.t("version.attribute_change.#{key}",
      attr: item_class.human_attribute_name(attr),
      from: ERB::Util.html_escape(from), to: ERB::Util.html_escape(to)).html_safe
  end

  # The plan written out, e.g. "2026-02: 312,50€, 2026-03: 500€".
  def raw_installments_eur_change(attr, from, to)
    from = raw_installments_eur_text(from)
    to = raw_installments_eur_text(to)
    key = attribute_change_key(from, to)
    return "" unless key

    I18n.t("version.attribute_change.#{key}",
      attr: item_class.human_attribute_name(attr),
      from: ERB::Util.html_escape(from), to: ERB::Util.html_escape(to)).html_safe
  end

  # "Lastschrift" / "Überweisung".
  def payment_method_change(attr, from, to)
    from = Wsjrdp2027::ParticipationFee.payment_method_label(from)
    to = Wsjrdp2027::ParticipationFee.payment_method_label(to)
    key = attribute_change_key(from, to)
    return "" unless key

    I18n.t("version.attribute_change.#{key}",
      attr: item_class.human_attribute_name(attr),
      from: ERB::Util.html_escape(from), to: ERB::Util.html_escape(to)).html_safe
  end

  # The stored plan [starting year, euros per month from January] written
  # out; nil for none, "keine Raten" for a plan of zeros only.
  def raw_installments_eur_text(value)
    year, *eur = Array(value)
    return nil if year.nil?

    h.installments_text(Wsjrdp2027::PaymentPlanConversionHelper.year_and_eur_a_to_yme_list(year.to_i, eur)) ||
      "keine Raten"
  end

  # One line per changed value of the record, in the order the record lists
  # them and in the words the Abmeldung page's flash uses -- the record itself
  # says them, so the two cannot drift apart. A value the record does not know
  # has no line.
  def deregistration_record_change(from, to)
    before = deregistration_record_hash(from)
    after = deregistration_record_hash(to)
    lines = Wsjrdp2027::DeregistrationRecord::ATTRS
      .reject { |key| Wsjrdp2027::DeregistrationRecord.same?(key, before[key], after[key]) }
      .map { |key| Wsjrdp2027::DeregistrationRecord.describe_change(key, before[key], after[key]) }

    h.safe_join(lines, h.tag.br)
  end

  # The stored sub-object with string keys; anything but a Hash counts as no
  # values, so a nil side (the key added or removed) works like an empty one.
  def deregistration_record_hash(value)
    value.is_a?(Hash) ? value.stringify_keys : {}
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
