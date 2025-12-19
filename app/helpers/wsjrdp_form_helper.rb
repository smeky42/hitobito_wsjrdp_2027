# frozen_string_literal: true

#  Copyright (c) 2025 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module WsjrdpFormHelper
  extend ActiveSupport::Concern

  included do
    def form_like_labeled_attr(obj, attr, display_link: true)
      key = captionize(attr, object_class(obj))
      val = format_attr(obj, attr, display_link: display_link)
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
          form.labeled_input_field(a, **opts)
        elsif !block_given? || yield(a)
          a_display = :"#{a}_display"
          a = a_display if obj.respond_to?(a_display)
          form_like_labeled_attr(obj, a, display_link: display_link)
        end
      end
    end
  end
end
