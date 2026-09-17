# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "typst"

module Wsjrdp2027
  # Compiles one of the wagon's Typst templates to a PDF.
  #
  # The contract:
  #
  # - `template` is a file name inside TEMPLATE_DIR (e.g. "refund_receipt.typ").
  #   That directory is also the Typst project root, so a template reaches its
  #   siblings -- `#import "wsjrdp2027.typ"` and the letterhead the shared
  #   template pulls in as a page background.
  # - `sys_inputs` become Typst's `sys.inputs`, which are Strings and nothing
  #   else. Every value is stringified here; structured data goes in as JSON and
  #   comes back out with Typst's `json(bytes(...))`.
  # - The return value is the whole PDF as one binary String.
  #
  # The fonts come from the wagon's own font directory rather than the system,
  # so the output does not depend on what is installed where it runs.
  #
  # See doc/typst_documents.md.
  class TypstDocument
    # Next to the domain code that fills the templates, the way the core keeps
    # its own PDF assets (app/domain/invoice/assets). Zeitwerk leaves the
    # directory alone: it holds no .rb file.
    TEMPLATE_DIR = ["app", "domain", "wsjrdp_2027", "typst"].freeze
    FONT_DIR = ["app", "assets", "fonts"].freeze

    class << self
      def compile_pdf(template, sys_inputs: {})
        pdf = Typst(template_path(template).to_s)
          .with_root(typst_dir.to_s)
          .with_font_paths([fonts_dir.to_s])
          .with_inputs(stringify(sys_inputs))
          .compile(:pdf)
          .pages
          .first
        raise "Typst produced no PDF for #{template}" unless pdf&.start_with?("%PDF")

        pdf
      end

      def typst_dir = HitobitoWsjrdp2027::Wagon.root.join(*TEMPLATE_DIR)

      def fonts_dir = HitobitoWsjrdp2027::Wagon.root.join(*FONT_DIR)

      private

      # Templates live in TEMPLATE_DIR and nowhere else: a name is a file name,
      # never a path.
      def template_path(template)
        name = File.basename(template.to_s)
        path = typst_dir.join(name)
        raise ArgumentError, "Unknown typst template: #{template}" unless path.file?

        path
      end

      def stringify(sys_inputs)
        sys_inputs.to_h { |key, value| [key.to_s, value.to_s] }
      end
    end
  end
end
