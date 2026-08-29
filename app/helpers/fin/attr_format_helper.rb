# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The finance sibling of hitobito's FormatHelper#format_attr: the same
# respond_to?-on-the-view-context lookup and the same model-name rule, plus the
# Fin::AttrFormatContext every finance formatter sees and a finance type layer
# in front of the core chain.
#
# A field's helper is found in this order (most specific first):
#
#   fin_format_<subclass>_<attr>     STI only, when it differs from the base class
#   fin_format_<base_class>_<attr>   the core's rule
#   fin_format_<attr>                model-wide fields (moss_status, iban, ...)
#   finance type rules               dates, arrays, *_cents / *_amount
#   wsjrdp_format_attr               hitobito's chain (enum labels, links, ...)
#
# A formatter takes (obj, ctx) -- or (obj) alone for a one-liner -- and returns
# a String, an html-safe buffer, nil (a blank value), a Hash or a
# Fin::DetailValue; #fin_format_attr always answers with a Fin::DetailValue.
#
# The raw half (#fin_raw_format) formats one entry of a jsonb column for a raw
# block; there nil means "nothing special, use the default formatting", because
# that helper is asked about every key of the export.
module Fin::AttrFormatHelper
  # Formats `attr` of `obj` for `ctx`; always returns a Fin::DetailValue.
  def fin_format_attr(obj, attr, ctx)
    name = fin_formatter_names(obj, attr).find { |n| respond_to?(n) }
    Fin::DetailValue.wrap(
      name ? fin_call_formatter(name, obj, ctx) : fin_format_attr_by_type(obj, attr, ctx)
    )
  end

  # Candidate helper names of a field, most specific first.
  def fin_formatter_names(obj, attr)
    fin_model_names(obj).map { |model| :"fin_format_#{model}_#{attr}" } << :"fin_format_#{attr}"
  end

  # A formatter takes (obj, ctx); (obj) alone is accepted for one-liners.
  def fin_call_formatter(name, obj, ctx)
    (method(name).arity == 1) ? send(name, obj) : send(name, obj, ctx)
  end

  # Finance type rules for attributes without a formatter, then hitobito's chain
  # (i18n enum labels, belongs_to / has_one links, booleans, decimals). A nil or
  # empty value is a blank value here and does NOT enter that chain, which would
  # answer with a non-breaking space. `false` and 0 are values.
  def fin_format_attr_by_type(obj, attr, _ctx)
    value = obj.public_send(attr)
    case value
    when nil, "" then nil
    when Date then fin_date(value)
    when ActiveSupport::TimeWithZone, Time then fin_date_time(value)
    when Array then value.compact_blank.join(", ").presence
    when Hash then raise ArgumentError, "#{attr} is a jsonb column, list it in d.raw_entries instead"
    else fin_format_money_or_core(obj, attr, value)
    end
  end

  # Whether the viewer may see this field at all -- consulted for every field
  # and every raw block; a field it says no to leaves no row behind.
  #
  # The declaration mechanism is not decided yet (plan §3.5): a per-model map
  # attribute -> ability action checked with can?, raw cancancan attribute
  # rules, or an inline `if can?` around a group in the partial. Until then
  # every field is visible, and this is the ONE place that changes.
  def fin_attr_visible?(_obj, _attr, _ctx) = true

  # Formats one entry of a raw block: the entries of the jsonb column named by
  # ctx.raw_source while that block renders, and the block's also: columns
  # (raw_source nil). Looks for fin_raw_format_other_<subclass> and then
  # fin_raw_format_other_<base_class>; nil from that helper -- and no helper at
  # all -- means the default formatting of the stored value. Always answers with
  # a Fin::DetailValue.
  def fin_raw_format(obj, key, ctx)
    name = fin_raw_formatter_names(obj).find { |n| respond_to?(n) }
    result = name ? send(name, obj, key, ctx) : nil
    return Fin::DetailValue.wrap(result) unless result.nil?

    Fin::DetailValue.new(value: fin_raw_default_format(fin_raw_value(obj, key, ctx)))
  end

  # Candidate raw helper names, most specific first.
  def fin_raw_formatter_names(obj)
    fin_model_names(obj).map { |model| :"fin_raw_format_other_#{model}" }
  end

  # The stored value behind a raw entry: an entry of the jsonb column while a
  # raw block renders, the column itself for one of its also: columns.
  def fin_raw_value(obj, key, ctx)
    ctx.raw_source ? obj.public_send(ctx.raw_source).to_h[key] : obj.public_send(key)
  end

  # Raw means as stored: a date in the finance notation, a boolean as the word
  # the export wrote, nested JSON compact on one line, everything else as it is.
  def fin_raw_default_format(value)
    case value
    when nil then nil
    when true, false then value.to_s
    when Date then fin_date(value)
    when ActiveSupport::TimeWithZone, Time then fin_date_time(value)
    when Hash, Array then value.to_json
    else value.to_s
    end
  end

  # The model parts of a helper name: the STI subclass first (an extension over
  # the core rule), then the base class hitobito itself would use.
  def fin_model_names(obj)
    klass = object_class(obj)
    classes = klass.respond_to?(:base_class) ? [klass, klass.base_class].uniq : [klass]
    classes.map { |k| k.name.underscore.tr("/", "_") }
  end

  private

  # The narrow money rules: *_cents integers and *_amount decimals in the base
  # currency. An amount on another currency axis (doc/fin/money_conventions.md)
  # gets an explicit formatter -- these are a fallback, not a currency model.
  def fin_format_money_or_core(obj, attr, value)
    if attr.to_s.end_with?("_cents")
      fin_money(value.to_d / 100)
    elsif value.is_a?(BigDecimal) && attr.to_s.end_with?("_amount")
      fin_money(value)
    else
      wsjrdp_format_attr(obj, attr)
    end
  end
end
