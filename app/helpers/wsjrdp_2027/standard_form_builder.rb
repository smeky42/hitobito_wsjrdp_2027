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

  def mail_addresses_field(attr, html_options = {})
    html_options[:class] = html_options[:class].to_s
    html_options[:class] += " is-invalid" if errors_on?(attr)
    html_options[:class] = [
      html_options[:class], *StandardFormBuilder::FORM_CONTROL_WITH_WIDTH
    ].compact.join(" ")
    text_area(attr, html_options)
  end

  # The core's service token form lists the areas of "Rechte" as checkboxes;
  # people, groups and events get the area's :log extra in the same line
  # (service_tokens/_log_scope_field, Wsjrdp2027::ServiceTokenScopes).
  def boolean_field(attr, html_options = {})
    field = super
    return field unless object.is_a?(::ServiceToken)

    log_scope = Wsjrdp2027::ServiceTokenScopes.log_scope(attr) if Wsjrdp2027::ServiceTokenScopes::CORE_AREAS.include?(attr.to_s)
    return field unless log_scope

    content_tag(:div, class: "d-flex flex-wrap align-items-baseline gap-3") do
      field + template.render("service_tokens/log_scope_field", f: self, area: attr.to_s, scope: log_scope)
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
end
