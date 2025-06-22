# frozen_string_literal: true

module Wsjrdp2027
  module Export::Pdf
    module Registration
      class Runner
        def render(person, pdf_preview)
          new_pdf(person, pdf_preview).render
        end

        # rubocop:disable Metrics/AbcSize
        # rubocop:disable Metrics/MethodLength
        def new_pdf(person, pdf_preview)
          pdf = Prawn::Document.new(page_size: "A4", page_layout: :portrait, margin: 2.cm, bottom_margin: 1.cm)

          @person = PersonDecorator.new(person)

          sections.each do |section|
            section.new(pdf, @person).render
            pdf.start_new_page if section != sections.last
          end

          # define header & footer variables
          # ToDo relative to root
          image_path = "../hitobito_wsjrdp_2027/app/assets/images/"

          pdf.y = 850
          # pdf.page_count = 0
          pdf.repeat :all do
            # define header
            if pdf_preview
              pdf.bounding_box [150, 750], width: pdf.bounds.width, height: 200 do
                pdf.transparent(0.5) do
                  pdf.text "Vorschau:", size: 24
                  pdf.text "Nicht zum upload gedacht!", size: 12
                  pdf.text "Bitte nutze die Anmeldung unter", size: 12
                  pdf.text '"Verbindlich drucken".', size: 12
                end
              end
            end

            logo = Rails.root.join(image_path + "wsjrdp-logo.png")
            pdf.bounding_box [350, 800], width: pdf.bounds.width, height: 375 do
              pdf.image logo, width: 150
              # pdf.move_up 15
            end

            pdf.bounding_box [pdf.bounds.left, pdf.bounds.bottom + 10], width: pdf.bounds.width do
              pdf.text person.id.to_s + " - " + person.full_name + " " \
               + person.birthday.strftime("%d.%m.%Y"), size: 8
            end
          end

          pdf.number_pages "Seite <page> von <total>",
            at: [pdf.bounds.left, pdf.bounds.bottom], size: 8

          pdf
        end
        # rubocop:enable Metrics/AbcSize
        # rubocop:enable Metrics/MethodLength

        def customize(pdf)
          pdf.font_size 9
          pdf
        end

        def sections
          # if @person.role_wish == "Unit Leitung"
          #   return [Contract, Medicin, DataProcessing, Recommondation, Travel, DataAgreement]
          # end
          # if @person.role_wish == "Kontingentsteam"
          #   return [Contract, Medicin, DataProcessing, Travel, DataAgreement]
          # end

          # [Contract, Medicin, Travel, DataAgreement]
          [Contract, Medical]
        end
      end
      mattr_accessor :runner
      self.runner = Runner

      def self.render(person, pdf_preview)
        runner.new.render(person, pdf_preview)
      end

      def self.new_pdf(person, pdf_preview)
        runner.new.new_pdf(person, pdf_preview)
      end
    end
  end
end
