# frozen_string_literal: true

module Wsjrdp2027
  module Export::Pdf::Registration
    class Section
      attr_reader :pdf

      class_attribute :model_class
      class_attribute :name

      delegate :bounds, :bounding_box, :table,
        :text, :cursor, :font_size, :text_box,
        :fill_and_stroke_rectangle, :fill_color,
        :image, :group, to: :pdf

      def initialize(pdf, person)
        @pdf = pdf
        @person = person
      end

      private

      def render_section(section_class)
        section_class.new(pdf, person).render
      end

      def with_settings(opts = {})
        before = opts.map { |key, _value| [key, pdf.send(key)] }
        opts.each { |key, value| pdf.send(:"#{key}=", value) }
        yield
        before.each { |key, value| pdf.send(:"#{key}=", value) }
      end

      def render_columns(left, right)
        bounding_box([0, cursor], width: bounds.width) do
          gutter = 10
          width = (bounds.width / 2) - (gutter / 2)
          starting_page = pdf.page_number

          pdf.span(width, {position: 0}, &left)
          pdf.go_to_page(starting_page)
          pdf.span(width, {position: width + gutter}, &right)
        end
        move_down_line
      end

      def stroke_bounds
        # pdf.stroke_bounds
      end

      def with_header(header)
        heading { text header, style: :bold }
        move_down_line
        yield
        2.times { move_down_line }
      end

      def text(*args)
        options = args.extract_options!
        pdf.text args.join(" "), options
      end

      def move_down_line(line = 10)
        pdf.move_down(line)
      end

      def heading(&block)
        font_size(11, &block)
      end

      def labeled_attr(model, attr)
        value = model.send(attr)
        text [model.class.human_attribute_name(attr), f(value)].join(": ") if value.present?
      end

      def f(value)
        case value
        when Date then I18n.l(value)
        when Time then I18n.l(value, format: :time)
        when true then I18n.t(:"global.yes")
        when false then I18n.t(:"global.no")
        else value.to_s
        end
      end

      def human_event_name
        event.class.model_name.human
      end

      def human_participant_name
        ::Event::Role::Participant.model_name.human
      end

      def human_attribute_name(attr, model)
        model.class.human_attribute_name(attr)
      end

      def document_id
        Base64.encode64(@person.id.to_s + Time.zone.today.strftime("%d.%m.%Y"))
      end

      def event_with_kind?
        event.used_attributes.include?(:kind_id)
      end

      def i18n_event_postfix
        event.class.to_s.underscore.tr("/", "_")
      end
    end
  end
end
