# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# What a finance formatter hands back, normalised. A formatter
# (fin_format_<model>_<attr>, fin_raw_format_other_<model>) may return a String,
# an html-safe buffer, nil, a Hash with these keys, or a DetailValue:
#
#   value    the text / HTML of the field
#   help     the field's comment -- a muted line under the value
#   tooltip  explanation of the LABEL, rendered as its title
#   label    a one-off label, in place of the i18n one
#   blank    what to do when value is blank: :hide, :dash, :empty or :unset
#   hide     drop the row whatever the value is
#
# A Hash with an unknown key raises, which is the typo guard: `{tooltop: "..."}`
# must not silently vanish. Because #wrap accepts a plain String, a one-line
# formatter never sees any of this.
class Fin::DetailValue < Data.define(:value, :help, :tooltip, :label, :blank, :hide)
  # What #blank may ask for when the value is blank: drop the row, a muted em
  # dash, the label with an empty value, or the muted words "nicht gesetzt".
  BLANK_MODES = %i[hide dash empty unset].freeze

  def initialize(value: nil, help: nil, tooltip: nil, label: nil, blank: nil, hide: false)
    if blank && !BLANK_MODES.include?(blank)
      raise ArgumentError, "blank must be one of #{BLANK_MODES.join(", ")}"
    end
    super
  end

  def self.wrap(result)
    case result
    when Fin::DetailValue then result
    when Hash then new(**result)
    else new(value: result)
    end
  end

  # `false` is a value (hitobito's attr_present? rule), "" and nil are blank.
  def blank_value? = value.nil? || (value.respond_to?(:empty?) && value.empty?)
end
