# frozen_string_literal: true

module BuddyIdHelper
  extend ActiveSupport::Concern

  def get_random_spice
    spice = spice_yaml
    "#{spice[rand(1...78)]}-#{spice[rand(1...78)]}"
  end

  def spice_yaml
    YAML.load_file(HitobitoWsjrdp2027::Wagon.root.join("config/spice.yml"))
  end
end
