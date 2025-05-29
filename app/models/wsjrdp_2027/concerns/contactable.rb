# frozen_string_literal: true

module Wsjrdp2027::Concerns::Contactable
  # Overriding zip_country from Hitobito's Contactable
  # To validate zip codes to German zip code format when country is nil, we return :de format as the default
  # option when country is nil
  def zip_country
    self[:country] || :de
  end
end
