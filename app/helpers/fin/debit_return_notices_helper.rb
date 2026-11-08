# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The mails about a returned direct debit, as the detail of its Beitragsbuchung
# shows them (fin/accounting_entries/_debit_return_notices). A script that sends
# such a mail (wsjrdp_scripts: accounting_tools/missing_installment.py) leaves
# two traces: an element of the entry's additional_info
# (AccountingEntry#debit_return_notifications) and a note in the person's log
# (a `versions` row, event wsjrdp_note, category debit_return, its item the
# entry -- doc/wsjrdp/log_entries.md). The element names its note
# (log_version_id); a note no element names is shown as well, from its own
# data.
module Fin::DebitReturnNoticesHelper
  NOTE_CATEGORY = "debit_return"

  DebitReturnNotice = Data.define(:sent_at, :subject, :to, :cc, :message_id, :issue, :log_note)

  # The mails, oldest first.
  def fin_debit_return_notices(entry)
    stored = entry.debit_return_notifications
    notes = fin_debit_return_notes(entry, stored.filter_map { |n| n["log_version_id"] }).index_by(&:id)
    notices = stored.map { |n| fin_debit_return_notice(n, notes.delete(n["log_version_id"])) }
    notices += notes.values.map { |note| fin_debit_return_notice(note.wsjrdp_data, note) }
    notices.sort_by { |n| n.sent_at || Time.zone.at(0) }
  end

  # The note in the person's log, shown as the log page shows it
  # (PaperTrail::VersionDecorator#changes, "<i>Rücklastschrift</i>: …").
  def fin_debit_return_log_note(note)
    note && PaperTrail::VersionDecorator.new(note).changes
  end

  private

  def fin_debit_return_notes(entry, ids)
    versions = PaperTrail::Version.where(event: Wsjrdp::LogEvents::NOTE)
    on_entry = versions.where(item_type: "AccountingEntry", item_id: entry.id)
      .where("wsjrdp_data @> ?", {category: NOTE_CATEGORY}.to_json)
    on_entry.or(versions.where(id: ids)).to_a
  end

  def fin_debit_return_notice(data, note)
    data ||= {}
    DebitReturnNotice.new(
      sent_at: fin_debit_return_time(data["sent_at"]) || note&.created_at,
      subject: data["email_subject"].presence,
      to: Array(data["email_to"]).compact_blank,
      cc: Array(data["email_cc"]).compact_blank,
      message_id: data["email_message_id"].presence,
      issue: data["debit_return_issue"].presence,
      log_note: note
    )
  end

  def fin_debit_return_time(value)
    Time.zone.parse(value.to_s) if value.present?
  rescue ArgumentError
    nil
  end
end
