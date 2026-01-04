# frozen_string_literal: true

#  Copyright (c) 2025 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module WsjrdpFormHelper
  extend ActiveSupport::Concern

  def wsjrdp_format_attr(obj, attr, display_link: true)
    if (assoc = association(obj, attr, :has_one))
      format_assoc(obj, assoc)
    else
      format_attr(obj, attr, display_link: display_link)
    end
  end

  def wsjrdp_labeled_input_field(form, attr, **options) # rubocop:disable Metrics/MethodLength
    # based on `build_labeled_field` in standard_form_builder.rb
    label = options.delete(:label)
    label_class = options.delete(:label_class)
    addon = options.delete(:addon)
    help = options.delete(:help)
    help_inline = options.delete(:help_inline)

    caption = label if label.present?

    content = wsjrdp_input_field(form, attr, **options)
    content = form.with_addon(addon, content) if addon.present?
    wsjrdp_with_labeled_field_help(form, attr, help, help_inline) { |element| content << element }
    form.labeled(attr, caption, content, required: options[:required], label_class: label_class)
  end

  def wsjrdp_input_field(form, attr, **opts)
    obj = form.object
    type = opts.delete(:input_field_type)
    type = column_type(obj, attr.to_sym) if type.nil?
    if type == "Person"
      form.person_field(attr, **opts)
    elsif wsjrdp_association_kind?(attr, type, obj, :has_one)
      form.belongs_to_field(attr, **opts)
    else
      form.input_field(attr, **opts)
    end
  end

  def wsjrdp_association_kind?(attr, type, obj, *macros)
    if type == :integer || type.nil?
      assoc = association(obj, attr, *macros)
      assoc.present? && assoc.options[:polymorphic].nil?
    else
      false
    end
  end

  def wsjrdp_with_labeled_field_help(form, attr, help, help_inline)
    if help.present?
      yield form.help_inline(help_inline) if help_inline.present?
      yield form.help_block(help)
    else
      yield wsjrdp_help_texts(form).render_field(attr)
      yield form.help_inline(help_inline) if help_inline.present?
    end
  end

  def wsjrdp_help_texts(form)
    @help_texts ||= HelpTexts::Renderer.new(form.template)
  end

  included do
    def form_like_labeled_attr(obj, attr, display_link: true)
      key = captionize(attr, object_class(obj))
      val = wsjrdp_format_attr(obj, attr, display_link: display_link)
      key_content = content_tag(:span, key, class: "col-md-3 col-xl-2 text-md-end")
      val_content = content_tag(:span, val, class: "labeled pb-1 col-md-9 col-lg-8 col-xl-8 mw-63ch")
      content_tag(:div, key_content + val_content, class: "row mb-2")
    end

    def input_or_render_attrs(form, *attrs, display_link: true, **opts)
      obj = form.object
      return if attrs.blank?
      permitted_attrs_set = permitted_attrs.to_set

      safe_join(attrs) do |a|
        if permitted_attrs_set.include?(a)
          a_input_field_options = :"#{a}_input_field_options"
          opts = obj.send(a_input_field_options).merge(opts) if obj.respond_to?(a_input_field_options)
          wsjrdp_labeled_input_field(form, a, **opts)
        elsif !block_given? || yield(a)
          a_display = :"#{a}_display"
          a = a_display if obj.respond_to?(a_display)
          form_like_labeled_attr(obj, a, display_link: display_link)
        end
      end
    end
  end
end
