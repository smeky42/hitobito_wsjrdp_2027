require "geocoder"

Geocoder.configure(
  lookup: :nominatim,
  http_headers: {"User-Agent" => "German Contingent for the World Scout Jamboree 2027 (admin@worldscoutjamboree.de)"},
  timeout: 5,
  units: :km
)
