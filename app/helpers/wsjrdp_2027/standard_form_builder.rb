# frozen_string_literal: true

#  Copyright (c) 2025 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027::StandardFormBuilder
  extend ActiveSupport::Concern

  included do
    def mail_addresses_field(attr, html_options = {})
      html_options[:class] = html_options[:class].to_s
      html_options[:class] += " is-invalid" if errors_on?(attr)
      html_options[:class] = [
        html_options[:class], *StandardFormBuilder::FORM_CONTROL_WITH_WIDTH
      ].compact.join(" ")
      text_area(attr, html_options)
    end
  end
end
