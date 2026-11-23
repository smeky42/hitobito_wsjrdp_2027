# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The chips at the foot of a description cell: what the row's hidden columns
# would show (its dates, kind and account). Shared by the account tables and
# the Moss transactions list.
module Fin::RowChipsHelper
  # A row's kind as a chip, in the look of the Moss kind chips (Fin::AccountKinds).
  def account_kind_chip(kind)
    content_tag(:span, class: "moss-kind #{Fin::AccountKinds.css_class(kind)}", title: Fin::AccountKinds.hint(kind)) do
      safe_join([content_tag(:i, "", class: "fas fa-#{Fin::AccountKinds.icon(kind)}", "aria-hidden": "true"),
        Fin::AccountKinds.label(kind)], " ")
    end
  end

  # An account as an outlined chip with its icon (bank or wallet).
  def account_chip(name, icon)
    content_tag(:span, safe_join([content_tag(:i, "", class: "fas fa-#{icon}", "aria-hidden": "true"), name], " "),
      class: "fin-account-chip")
  end

  # How a row's dates show (fin_date_chips): the booking day always while its
  # column is hidden, else on a phone alone, where the column (mobile: false)
  # gives way; the value date while its column is hidden. `value: nil` for a
  # table without one (Moss).
  def fin_date_chip_modes(state, booking_label:, booking: "booking_date", value: "value_date")
    {booking: state.column_hidden?(booking) ? :always : :mobile,
     booking_label: state.column_label(booking, booking_label),
     value: !value.nil? && state.column_hidden?(value)}
  end

  # The date columns whose sorts move into the description's header: hidden,
  # but not never shown.
  def fin_hidden_date_keys(state, keys = %w[booking_date value_date])
    keys.select { |key| state.column_hidden?(key) && !state.column_never?(key) }
  end

  # A row's date chips (fin_date_chip_modes): its booking day, and a bank row's
  # value date where it differs from the booking day.
  def fin_date_chips(modes, booking_date:, value_date: nil)
    [fin_date_chip(modes[:booking_label], booking_date, only_mobile: modes[:booking] == :mobile),
      (fin_date_chip("Valuta", value_date) if modes[:value] && value_date && value_date != booking_date)]
  end

  # A date as an outlined chip. `only_mobile`: shown on a phone alone.
  def fin_date_chip(label, date, only_mobile: false)
    return if date.nil?

    content_tag(:span, safe_join([content_tag(:i, "", class: "far fa-calendar", "aria-hidden": "true"),
      "#{label} #{fin_date(date)}"], " "), class: ["fin-account-chip", ("d-md-none" if only_mobile)])
  end

  # The chips line at the foot of a description cell; nil without a chip.
  def fin_row_chips(chips)
    chips = chips.compact
    content_tag(:div, safe_join(chips), class: "fin-row-chips") if chips.any?
  end
end
