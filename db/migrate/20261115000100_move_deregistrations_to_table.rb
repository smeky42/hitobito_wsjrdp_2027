# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Moves the deregistration data of people.additional_info into
# wsjrdp_deregistrations: one row (number 1) per person with any of the keys,
# the mails the form went out with as events. The status is read from what
# was done: finished for a person deregistered, form_sent once a mail went
# out, form_created once the form was made, recorded otherwise.
#
# down writes the keys back from the current row of each person (the open
# one, else the latest) and empties both tables -- rows made after the
# migration are folded into those keys, earlier versions are lost.
class MoveDeregistrationsToTable < ActiveRecord::Migration[7.1]
  FLAT_KEYS = %w[
    deregistration_issue deregistration_requested_date deregistration_effective_date
    deregistration_actual_compensation_cents deregistration_record
  ].freeze
  FINAL_STATUSES = %w[finished canceled superseded deleted].freeze

  def up
    keys = sql_array(FLAT_KEYS)
    execute <<~SQL
      INSERT INTO wsjrdp_deregistrations (
        person_id, number, status, kind, issue, requested_date, effective_date, reply_due_date,
        actual_compensation, show_contractual_compensation, form_snapshot, form_sent_at, closed_at,
        additional_info, created_at, updated_at)
      SELECT src.person_id, 1,
        CASE WHEN src.person_status = 'deregistered' THEN 'finished'
             WHEN jsonb_array_length(COALESCE(src.rec->'form_mailings', '[]'::jsonb)) > 0 THEN 'form_sent'
             WHEN src.rec ? 'form_created_date' THEN 'form_created'
             ELSE 'recorded' END,
        COALESCE(NULLIF(src.rec->>'kind', ''), 'withdrawal'),
        NULLIF(src.ai->>'deregistration_issue', ''),
        NULLIF(src.ai->>'deregistration_requested_date', '')::date,
        NULLIF(src.ai->>'deregistration_effective_date', '')::date,
        NULLIF(src.rec->>'reply_due_date', '')::date,
        (NULLIF(src.ai->>'deregistration_actual_compensation_cents', '')::numeric / 100),
        COALESCE((src.rec->>'form_show_contractual_compensation')::boolean, true),
        jsonb_strip_nulls(jsonb_build_object(
          'created_date', src.rec->'form_created_date',
          'effective_reply_due_date', src.rec->'effective_reply_due_date',
          'refund_account_holder', src.rec->'refund_account_holder',
          'refund_iban', src.rec->'refund_iban',
          'refund_bic', src.rec->'refund_bic',
          'refund_sepa_address', src.rec->'refund_sepa_address',
          'person_role', src.rec->'person_role',
          'person_role_name', src.rec->'person_role_name',
          'person_team_unit', src.rec->'person_team_unit')),
        (src.rec->'form_mailings'->0->>'email_sent_at')::timestamptz,
        CASE WHEN src.person_status = 'deregistered' THEN now() END,
        CASE WHEN src.receipt = '{}'::jsonb THEN '{}'::jsonb ELSE jsonb_build_object('refund_receipt', src.receipt) END,
        now(), now()
      FROM (
        SELECT p.id AS person_id, p.status AS person_status, p.additional_info AS ai,
          COALESCE(p.additional_info->'deregistration_record', '{}'::jsonb) AS rec,
          jsonb_strip_nulls(jsonb_build_object(
            'created_date', p.additional_info->'deregistration_record'->'receipt_created_date',
            'created_by_id', p.additional_info->'deregistration_record'->'receipt_created_by_id',
            'snapshot', p.additional_info->'deregistration_record'->'receipt_snapshot',
            'text', p.additional_info->'deregistration_record'->'refund_receipt_text',
            'show_default_explanation',
              p.additional_info->'deregistration_record'->'refund_receipt_show_default_explanation')) AS receipt
        FROM people p
        WHERE p.additional_info ?| #{keys}
          AND NOT EXISTS (SELECT 1 FROM wsjrdp_deregistrations d WHERE d.person_id = p.id)
      ) src
    SQL

    execute <<~SQL
      INSERT INTO wsjrdp_deregistration_events (deregistration_id, event, action, to_status, occurred_at, comment)
      SELECT d.id, 'create', 'migrated', d.status, now(), 'aus people.additional_info übernommen'
      FROM wsjrdp_deregistrations d
      WHERE NOT EXISTS (SELECT 1 FROM wsjrdp_deregistration_events e WHERE e.deregistration_id = d.id)
    SQL

    execute <<~SQL
      INSERT INTO wsjrdp_deregistration_events (deregistration_id, event, action, occurred_at, additional_info)
      SELECT d.id, 'notify', 'form_sent', COALESCE((m.value->>'email_sent_at')::timestamptz, now()), m.value
      FROM wsjrdp_deregistrations d
      JOIN people p ON p.id = d.person_id
      CROSS JOIN LATERAL jsonb_array_elements(
        COALESCE(p.additional_info->'deregistration_record'->'form_mailings', '[]'::jsonb))
        WITH ORDINALITY AS m(value, ordinality)
      ORDER BY d.id, m.ordinality
    SQL

    execute("UPDATE people SET additional_info = additional_info - #{keys} WHERE additional_info ?| #{keys}")
  end

  def down
    keys = sql_array(FLAT_KEYS)
    finals = sql_array(FINAL_STATUSES)
    execute <<~SQL
      WITH cur AS (
        SELECT DISTINCT ON (d.person_id) d.*
        FROM wsjrdp_deregistrations d
        ORDER BY d.person_id, (d.status = ANY(#{finals})), d.number DESC
      ), rec AS (
        SELECT cur.person_id,
          jsonb_strip_nulls(jsonb_build_object(
            'kind', NULLIF(cur.kind, 'withdrawal'),
            'reply_due_date', cur.reply_due_date,
            'effective_reply_due_date', cur.form_snapshot->'effective_reply_due_date',
            'form_created_date', cur.form_snapshot->'created_date',
            'receipt_created_date', cur.additional_info->'refund_receipt'->'created_date',
            'receipt_created_by_id', cur.additional_info->'refund_receipt'->'created_by_id',
            'refund_account_holder', cur.form_snapshot->'refund_account_holder',
            'refund_iban', cur.form_snapshot->'refund_iban',
            'refund_bic', cur.form_snapshot->'refund_bic',
            'refund_sepa_address', cur.form_snapshot->'refund_sepa_address',
            'person_role', cur.form_snapshot->'person_role',
            'person_role_name', cur.form_snapshot->'person_role_name',
            'person_team_unit', cur.form_snapshot->'person_team_unit',
            'receipt_snapshot', cur.additional_info->'refund_receipt'->'snapshot',
            'form_show_contractual_compensation', CASE WHEN cur.show_contractual_compensation THEN NULL ELSE false END,
            'refund_receipt_text', cur.additional_info->'refund_receipt'->'text',
            'refund_receipt_show_default_explanation', cur.additional_info->'refund_receipt'->'show_default_explanation',
            'form_mailings', (SELECT jsonb_agg(e.additional_info ORDER BY e.occurred_at, e.id)
                              FROM wsjrdp_deregistration_events e
                              WHERE e.deregistration_id = cur.id AND e.event = 'notify' AND e.action = 'form_sent')
          )) AS record
        FROM cur
      )
      UPDATE people p
      SET additional_info = (p.additional_info - #{keys}) || jsonb_strip_nulls(jsonb_build_object(
        'deregistration_issue', cur.issue,
        'deregistration_requested_date', cur.requested_date,
        'deregistration_effective_date', cur.effective_date,
        'deregistration_actual_compensation_cents', round(cur.actual_compensation * 100)::integer,
        'deregistration_record', NULLIF(rec.record, '{}'::jsonb)))
      FROM cur JOIN rec ON rec.person_id = cur.person_id
      WHERE p.id = cur.person_id
    SQL
    execute("DELETE FROM wsjrdp_deregistrations")
  end

  private

  def sql_array(values) = "ARRAY[#{values.map { |v| connection.quote(v) }.join(", ")}]::text[]"
end
