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

  def _url_host_allowed?(url)
    URI(url.to_s).host == request.host
  rescue ArgumentError, URI::Error
    false
  end

  included do
    def form_like_labeled(label, content = nil, &block)
      content = capture(&block) if block
      label_content = content_tag(:span, label, class: "col-md-3 col-xl-2 text-md-end")
      content_content = content_tag(:span, content, class: "labeled pb-1 col-md-9 col-lg-8 col-xl-8 mw-63ch")
      content_tag(:div, label_content + content_content, class: "row mb-2")
    end

    def form_like_labeled_attr(obj, attr, display_link: true)
      key = captionize(attr, object_class(obj))
      val = wsjrdp_format_attr(obj, attr, display_link: display_link)
      form_like_labeled(key, val)
    end

    def input_or_render_attrs(form, *attrs, display_link: true, show_previous_as_help_inline: false, **opts)
      obj = form.object
      return if attrs.blank?
      permitted_attrs_set = permitted_attrs.to_set

      safe_join(attrs) do |a|
        if permitted_attrs_set.include?(a)
          a_input_field_options = :"#{a}_input_field_options"
          a_opts = opts
          a_opts = obj.send(a_input_field_options).merge(opts) if obj.respond_to?(a_input_field_options)
          if show_previous_as_help_inline
            current_val = obj.send(a)
            if current_val.present?
              a_opts[:help_inline] = "Bisheriger Wert: ".html_safe + format_attr(obj, a)
            end
          end
          wsjrdp_labeled_input_field(form, a, **a_opts)
        elsif !block_given? || yield(a)
          a_display = :"#{a}_display"
          a = a_display if obj.respond_to?(a_display)
          form_like_labeled_attr(obj, a, display_link: display_link)
        end
      end
    end

    def render_attrs_list(&block)
      content = capture(&block)
      content_tag(:dl, content, class: "dl-horizontal m-0 p-2 border-top")
    end

    def labeled_attr_with_help(entry, attr, display_link: true, label: nil, help_text: nil, &block)
      help_content = capture(&block)
      label = captionize(attr, object_class(entry)) if label.nil?
      content = safe_join([
        format_attr(entry, attr),
        content_tag(:div, help_content, class: "muted")
      ])
      labeled(label, content)
    end

    # Returns the value of the Turbo-Frame header (the frame's ID)
    def turbo_frame_request_id
      request.headers["Turbo-Frame"]
    end

    def turbo_frame_request?
      turbo_frame_request_id.present?
    end

    def turbo_frame_if(condition, id, &block)
      if condition
        turbo_frame_tag(id, &block)
      else
        capture(&block)
      end
    end

    def turbo_frame_tag_if_frame_request(id, &block)
      if turbo_frame_request?
        turbo_frame_tag(id, &block)
      else
        capture(&block)
      end
    end

    # Wraps a detail view's body in the turbo frame THIS REQUEST asks for, and in
    # the page's #main when nobody asks (a direct visit). Used by the fin detail
    # views that double as the pane an expandable table lazy-loads.
    #
    # The requesting frame decides the id, because one and the same detail is
    # loaded from tables with different prefixes -- the Buchungen list asks as
    # "bkframe-bk-<id>", the bookings table embedded in a Buchhaltung item detail
    # as "bkframe-b-<id>" (its policy prefix is "b"). An id hardcoded in the view
    # answers the wrong frame, and Turbo renders "Content missing" instead of the
    # detail.
    #
    # `prefix` + `key` give the canonical id a direct visit gets, where the frame
    # only scopes the links inside it -- and `key` is also what a header must NAME
    # to be honoured (see #requested_detail_frame_id).
    def wsjrdp_detail_frame(prefix, key, &block)
      id = requested_detail_frame_id(key) || wsjrdp_detail_frame_id(prefix, key)
      frame = turbo_frame_tag(id) { safe_join([wsjrdp_detail_frame_flash, capture(&block)]) }
      turbo_frame_request? ? frame : content_tag(:div, frame, id: "main")
    end

    # The flash INSIDE the frame. A frame response renders turbo-rails' minimal
    # layout, which carries no flash slot -- so a detail that redirects to itself
    # after a save (Fin::BookingsController#redirect_after_update) would swallow
    # its own message. On a full page the layout renders the flash, and rendering
    # it here as well would show every message twice.
    def wsjrdp_detail_frame_flash
      return "".html_safe unless turbo_frame_request?

      render partial: "layouts/flash", collection: %i[notice warning alert], as: :level
    end

    # The `Turbo-Frame` header, honoured ONLY when it names a detail frame of THIS
    # record: "bkframe-<any table prefix>-<key>". Binding it to the key is what
    # keeps a STRAY header harmless -- a form inside an embedded pane submits with
    # the header of the row's frame, and its redirect may land on a detail PAGE of
    # another record; without this check that page would rename its own outer
    # frame to the row's id, so Turbo would find two nodes of that id and inject
    # the whole page into the row. Anything else falls back to the canonical id.
    def requested_detail_frame_id(key)
      id = turbo_frame_request_id
      id if id.present? && id.match?(/\Abkframe-[A-Za-z0-9_]+-#{Regexp.escape(key.to_s)}\z/)
    end

    def return_url_or_fallback(fallback)
      if params[:return_url].present?
        params[:return_url]
      elsif request.referer && _url_host_allowed?(request.referer)
        request.referer
      else
        fallback
      end
    end
  end
end
