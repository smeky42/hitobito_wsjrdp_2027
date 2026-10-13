# frozen_string_literal: true

#  Copyright (c) 2025, 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027::StandardFormBuilder
  # The core's service token form (service_tokens/_form) lists :name and
  # :description in its first fieldset; for an admin the acting person
  # follows there, as the core's person autocomplete over a search that
  # finds every person, by name or by id
  # (Wsjrdp::ServiceTokenActingPeopleController,
  # Wsjrdp2027::ActingPersonTokenAbility). The core's form stays as it is.
  def labeled_input_fields(*attrs)
    fields = super
    return fields unless object.is_a?(::ServiceToken) && attrs.include?(:description)
    return fields unless ::ServiceToken.acting_person_admin?(template.current_user)

    fields + labeled_person_field(:acting_person, help: I18n.t("service_tokens.acting_person_field.help"),
      data: {url: template.wsjrdp_service_token_acting_people_path})
  end

  # One country chosen from a list with search (tom-select, no value of its
  # own; shared/wsjrdp/_country_select_js), sent as its ISO code; with
  # labeled_, e.g. f.labeled_country_select_field(:country_of_birth). The
  # list shows "Deutschland (DE)" and also finds a country by its aliases
  # (Wsjrdp::CountryLookup.search_aliases, "USA"); × clears the choice. A
  # stored name the lookup knows is chosen as its code, any other value stays
  # a choice, marked, so saving does not drop it. value: preselects another
  # value than the stored one, e.g. a default; codes: offers only these
  # countries (Wsjrdp::CountryLookup::SCHENGEN_CODES).
  def country_select_field(attr, html_options = {})
    html_options = html_options.dup
    codes = html_options.delete(:codes)
    value = (html_options.key?(:value) ? html_options.delete(:value) : object.public_send(attr)).presence
    value = Wsjrdp::CountryLookup.find_country_by_any_name(value) || value if value
    select(attr, country_choices(Array(value), codes), {include_blank: true, selected: value},
      country_select_html_options(html_options)) +
      template.render("shared/wsjrdp/country_select_js")
  end

  # Several countries, as country_select_field, e.g.
  # f.labeled_country_multi_select_field(:passport_nationality_codes, help: ...).
  # The attribute answers a list of codes; value: preselects other codes,
  # e.g. a default. Rails' hidden empty value lets a cleared list reach the
  # model.
  def country_multi_select_field(attr, html_options = {})
    html_options = html_options.dup
    values = Array(html_options.key?(:value) ? html_options.delete(:value) : object.public_send(attr))
    select(attr, country_choices(values), {selected: values},
      country_select_html_options(html_options).merge(multiple: true)) +
      template.render("shared/wsjrdp/country_select_js")
  end

  def mail_addresses_field(attr, html_options = {})
    html_options[:class] = html_options[:class].to_s
    html_options[:class] += " is-invalid" if errors_on?(attr)
    html_options[:class] = [
      html_options[:class], *StandardFormBuilder::FORM_CONTROL_WITH_WIDTH
    ].compact.join(" ")
    text_area(attr, html_options)
  end

  # The core's service token form lists the areas of "Rechte" as checkboxes;
  # people, groups and events get the area's extras (people:log,
  # people:documents, ...) in the same line (service_tokens/_extra_scope_field,
  # Wsjrdp2027::ServiceTokenScopes).
  def boolean_field(attr, html_options = {})
    field = super
    return field unless object.is_a?(::ServiceToken)
    return field unless Wsjrdp2027::ServiceTokenScopes::CORE_AREAS.include?(attr.to_s)

    extras = Wsjrdp2027::ServiceTokenScopes::AREAS.fetch(attr.to_s).last
    return field if extras.empty?

    content_tag(:div, class: "d-flex flex-wrap align-items-baseline gap-3") do
      extras.reduce(field) do |line, scope|
        line + template.render("service_tokens/extra_scope_field", f: self, area: attr.to_s, scope: scope)
      end
    end
  end

  def labeled_inline_fields_for(
    assoc, partial = nil, record = nil, required = false,
    show_element_if: nil, allow_destroy_if: nil,
    &block
  ) # rubocop:disable Metrics/MethodLength
    html_options = {class: "labeled controls mb-3 mt-1 d-flex " \
                           "justify-content-start align-items-baseline"}
    css_classes = {row: true, "mb-2": true, required: required}
    label_classes = "control-label col-form-label col-md-3 col-xl-2 pb-1 text-md-end"
    label_classes += " required" if required
    content_tag(:div, class: css_classes.select { |_css, show| show }.keys.join(" ")) do
      label(assoc, class: label_classes) + content_tag(:div, class: "labeled col-md") do
        nested_fields_for(assoc, partial, record) do |fields|
          if show_element_if.nil? || show_element_if.call(fields&.object)
            content = block ? capture(fields, &block) : render(partial, f: fields)
            content = content_tag(:div, content, class: "col-md-10")
            content << content_tag(
              :div,
              if allow_destroy_if.nil? || allow_destroy_if.call(fields&.object)
                fields.link_to_remove(icon(:times))
              else
                content_tag(:span, icon(:times), style: "opacity: 0.1; margin: 5px;")
              end,
              class: "col-md-2"
            )
            content_tag(:div, content, html_options)
          end
        end
      end
    end
  end

  private

  # As wide as the other fields of the form; a placeholder: shows while
  # nothing is chosen.
  def country_select_html_options(html_options)
    html_options.merge(
      class: [html_options[:class],
        "form-select form-select-sm w-100 mw-100 mw-md-60ch wsjrdp-country-select"].compact.join(" "),
      data: {country_select: true, chosen_no_results: I18n.t("global.chosen_no_results")}
        .merge(html_options[:data] || {})
    )
  end

  # [German name, ISO code] of every country (or of codes), the frequent ones
  # first (Wsjrdp::CountryLookup::FREQUENT_CODES); before them each value that
  # is none of them.
  def country_choices(values, codes = nil)
    codes ||= ISO3166::Country.codes
    prioritized = Wsjrdp::CountryLookup::FREQUENT_CODES
    countries = codes.map do |code|
      [Wsjrdp::CountryLookup.german_name(code), code,
        {"data-code" => code, "data-aliases" => Wsjrdp::CountryLookup.search_aliases(code)}]
    end
    countries.sort_by! { |name, code, _data| [prioritized.index(code) || prioritized.size, I18n.transliterate(name)] }
    unknown = values.reject { |value| codes.include?(value) }
    unknown.map { |value| ["#{value} (#{I18n.t("country_codes.index.unknown")})", value] } + countries
  end
end
