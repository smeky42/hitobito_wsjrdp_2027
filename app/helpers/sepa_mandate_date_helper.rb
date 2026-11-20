# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module SepaMandateDateHelper
  # The collection dates of the person's announced direct debits, formatted:
  # pre-notified and not to be skipped. A debit already in a SEPA file
  # (xml_generated) no longer counts.
  def announced_direct_debit_dates(person)
    person.direct_debit_pre_notifications.where(payment_status: "pre_notified", try_skip: false)
      .pluck(:collection_date).map { |date| I18n.l(date) }
  end

  # Whether the typed mandate date (raw, the form's text) may be saved; else
  # an error on the person and false. A date is read by Wsjrdp::DateInput and
  # assigned to the person, not by the attribute's cast: that one takes
  # "1.2.26" for the year 1 and drops a text that is no date, which would
  # clear the date. Blank clears it on purpose. A person without a stored
  # date gets none (the print of the registration sets the first one).
  def sepa_mandate_date_valid?(person, raw)
    raw = raw.to_s.strip
    return true if raw.empty?

    date = Wsjrdp::DateInput.parse_or_nil(raw)
    error = if person.sepa_mandate_date_in_database.nil?
      t("people.sepa_account.mandate_date_before_print")
    elsif date.nil?
      t("people.sepa_account.mandate_date_invalid")
    end
    if error
      person.errors.add(:sepa_mandate_date, error)
      return false
    end

    # Assigning the stored date again changes nothing (no version).
    person.sepa_mandate_date = date
    true
  end

  # Whether the person keeps a stored mandate date while a direct debit is
  # announced; else the refusal as an error on the person and false.
  def sepa_mandate_date_kept?(person)
    return true unless (refusal = sepa_mandate_date_clearing_refusal(person))

    person.errors.add(:sepa_mandate_date, refusal)
    false
  end

  # Why the mandate date assigned to the person may not replace the stored
  # one: a text while it clears a stored date under an announced direct debit,
  # else nil.
  def sepa_mandate_date_clearing_refusal(person)
    return unless person.sepa_mandate_date_in_database && person.sepa_mandate_date.nil?

    dates = announced_direct_debit_dates(person)
    return if dates.empty?

    t("people.sepa_account.mandate_date_announced", dates: dates.join(", "))
  end

  # A warning next to the print of the registration while the mandate date
  # lies before it (the print sets the mandate date); else nil.
  def sepa_mandate_date_before_print_warning(person)
    mandate_date = person.sepa_mandate_date
    print_at = person.print_at_in_database&.to_date
    return unless mandate_date && print_at && mandate_date < print_at

    content_tag(:span, class: "text-warning") do
      safe_join([icon(:"exclamation-triangle"), " ",
        t("people.sepa_account.mandate_date_before_print_at", date: I18n.l(mandate_date))])
    end
  end
end
