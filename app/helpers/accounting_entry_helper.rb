# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module AccountingEntryHelper
  def format_accounting_entry_direct_debit_pre_notification(ae)
    _format_link_to(ae.direct_debit_pre_notification)
  end

  def format_accounting_entry_camt_transaction(ae)
    _format_link_to(ae.camt_transaction)
  end

  def format_accounting_entry_moss_booking(ae)
    _format_link_to(ae.moss_booking)
  end

  # The help under the edit form's Moss-Buchung field (finance manage): the link
  # as it is STORED -- moss_booking_id_in_database, so after a failed save the
  # help still names the old link while the field shows what was typed -- with
  # when, by whom and how it was made where moss_booking_link_meta knows it.
  def moss_booking_link_help(entry)
    id = entry.moss_booking_id_in_database
    howto = "Andere Nummer eintragen, um umzuhängen; leeres Feld oder „Verknüpfung lösen“ entfernt sie."
    return safe_join(["Bisher: keine Verknüpfung. Nummer einer Moss-Buchung eintragen, um zu verknüpfen."]) if id.nil?

    booking = MossBooking.includes(:moss_transaction).find_by(id: id)
    parts = [booking ? link_to(booking.link_name, booking) : "##{id}"]
    if booking
      parts << moss_kind_label(booking.moss_transaction.type)
      parts << fin_date(booking.moss_transaction.booking_date) if booking.moss_transaction.booking_date
    end
    provenance = link_provenance(entry.moss_booking_link_meta_in_database)
    parts << provenance if provenance
    safe_join(["Bisher: ", safe_join(parts, " · "), ". ", howto])
  end

  # "verknüpft am 05.10.2026 von <Person> (manuell)" from any *_link_meta hash
  # (doc/fin/recon_linking.md); nil when it records nothing.
  def link_provenance(meta)
    meta = meta.to_h
    return if meta["created_at"].blank? && meta["author_id"].blank?

    at = meta["created_at"].presence && fin_date(Time.zone.parse(meta["created_at"]))
    by = meta["author_id"].presence && Person.find_by(id: meta["author_id"])
    how = {"manual" => "manuell", "automatic" => "automatisch"}[meta["automatic_manual"]]
    ["verknüpft", ("am #{at}" if at), ("von #{by}" if by), ("(#{how})" if how)].compact.join(" ")
  end

  private

  def _format_link_to(obj)
    if obj.nil?
      content_tag(:span, "(keine)", class: "muted")
    elsif obj.respond_to?(:link_name)
      link_to(obj.link_name, obj)
    else
      link_to(obj)
    end
  end
end
