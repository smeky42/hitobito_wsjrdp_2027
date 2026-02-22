# frozen_string_literal: true

#  Copyright (c) 2025, 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027::StandardFormBuilder
  def mail_addresses_field(attr, html_options = {})
    html_options[:class] = html_options[:class].to_s
    html_options[:class] += " is-invalid" if errors_on?(attr)
    html_options[:class] = [
      html_options[:class], *StandardFormBuilder::FORM_CONTROL_WITH_WIDTH
    ].compact.join(" ")
    text_area(attr, html_options)
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
