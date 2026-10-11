# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The cells of the Zahlungscodes list (fin/payment_references/index) and the
# values of a code's page (fin/payment_references/_detail). Status and origin
# are worded by fin.payment_references.counts.* / .origins.*, a notice's status
# by fin.payment_references.notice_statuses.*.
module Fin::PaymentReferencesHelper
  # The widget's column Hashes, the full set (the columns menu picks from it).
  def payment_reference_table_columns
    cells = {
      "payment_code" => ->(reference) { payment_reference_code(reference) },
      "status" => ->(reference) { payment_reference_status_label(reference.status) },
      "origin" => ->(reference) { payment_reference_origin_label(reference.origin) },
      "created_at" => ->(reference) { payment_reference_time(reference.created_at) },
      "assigned_at" => ->(reference) { payment_reference_time(reference.assigned_at) },
      "notice_count" => ->(reference) { reference.notice_count },
      "comment" => ->(reference) { auto_link_escaped_multiline(reference.comment.to_s) }
    }
    Fin::PaymentReferencesColumns::COLUMNS.map { |col| col.to_table_column(cell: cells.fetch(col.key)) }
  end

  # The printed form, in the monospace face the code is read in.
  def payment_reference_code(reference)
    content_tag(:span, reference.printed_code, class: "font-monospace text-nowrap")
  end

  def payment_reference_status_label(status)
    t("fin.payment_references.counts.#{status}", default: status.to_s)
  end

  def payment_reference_origin_label(origin)
    t("fin.payment_references.origins.#{origin}", default: origin.to_s)
  end

  def payment_reference_notice_status_label(status)
    t("fin.payment_references.notice_statuses.#{status}", default: status.to_s)
  end

  def payment_reference_time(time)
    time && l(time, format: :short)
  end

  # The person a notice is for, linked out of the row's frame; any other
  # subject by type and id.
  def payment_reference_notice_subject(notice, people_by_id)
    person = (notice.subject_type == "Person") && people_by_id[notice.subject_id]
    return "#{notice.subject_type} ##{notice.subject_id}" unless person

    link_to(person.to_s, person_path(person), data: {turbo_frame: "_top"})
  end
end
