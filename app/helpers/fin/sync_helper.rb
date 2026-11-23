# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The pages of the Synchronisation (doc/fin/sync.md).
module Fin::SyncHelper
  STATE_CLASSES = {
    "planned" => "text-bg-primary", "applying" => "text-bg-info", "stopped" => "text-bg-warning",
    "applied" => "text-bg-success", "partly_applied" => "text-bg-warning", "failed" => "text-bg-danger",
    "cancelled" => "text-bg-secondary", "stale" => "text-bg-warning", "skipped" => "text-bg-secondary",
    "unchanged" => "text-bg-light border"
  }.freeze

  # The look of a notice per level: warning yellow, important blue, hint grey.
  NOTICE_ALERTS = {"warning" => "alert-warning", "important" => "alert-info", "hint" => "alert-secondary"}.freeze
  NOTICE_BADGES = {"warning" => "text-bg-warning", "important" => "text-bg-info", "hint" => "text-bg-secondary"}.freeze

  def fin_sync_notice_class(notice) = NOTICE_ALERTS.fetch(notice.level, "alert-info")

  def fin_sync_time(time) = time && l(time.in_time_zone, format: "%d.%m.%Y %H:%M:%S")

  def fin_sync_state(state, scope: :run)
    content_tag(:span, t("fin.sync.states.#{scope}.#{state}"), class: "badge #{STATE_CLASSES.fetch(state, "text-bg-light")}")
  end

  # "2 neu · 1 geändert" -- or "keine Änderungen".
  def fin_sync_counts(counts)
    shown = Wsjrdp::Sync::Plan::ACTIONS.filter_map do |action|
      count = counts.to_h[action].to_i
      t("fin.sync.actions.#{action}", count: count) if count.positive?
    end
    shown.presence&.join(" · ") || t("fin.sync.no_changes")
  end

  # The parts by their group in the tree: "Organisationsstruktur (Abteilungen,
  # Teams, Benutzer)"; groups apart by "; ".
  def fin_sync_selected_parts(keys)
    keys.group_by { |key| key.rpartition(".").first }.map do |group, members|
      parts = members.map { |key| fin_sync_part_label(key) }.join(", ")
      label = I18n.t("fin.sync.parts.#{group}._label", default: "")
      label.present? ? "#{label} (#{parts})" : parts
    end.join("; ")
  end

  def fin_sync_part_label(key) = Wsjrdp::Sync.part?(key) ? Wsjrdp::Sync.part(key).label : key

  # The class of a part; nil for a part no longer in the registry.
  def fin_sync_part_class(part) = Wsjrdp::Sync.part?(part.part_key) ? part.part_class : nil

  def fin_sync_runs_columns
    cells = {
      "id" => ->(run) { run.id },
      "started_at" => ->(run) { fin_sync_time(run.started_at) },
      "source" => ->(run) { fin_format_wsjrdp_sync_run_source(run) },
      "status" => ->(run) { fin_sync_state(run.status) },
      "parts" => ->(run) { fin_sync_selected_parts(run.selected_parts) },
      "started_by" => ->(run) { run.started_by.to_s },
      "duration" => ->(run) { fin_sync_duration(run.duration_ms) },
      "written" => ->(run) { fin_sync_stats(run.modified_rows) }
    }
    Wsjrdp::Sync::Stats::KEYS.each { |key| cells[key] = ->(run) { run.modified_rows[key] } }
    Fin::SyncRunsColumns::COLUMNS.map { |col| col.to_table_column(cell: cells.fetch(col.key)) }
  end

  # "4 eingefügt · 2 geändert" -- or "–".
  def fin_sync_stats(rows)
    shown = Wsjrdp::Sync::Stats::KEYS.filter_map do |key|
      count = rows[key]
      t("fin.sync.stats.#{key}", count: count) if count.positive?
    end
    shown.presence&.join(" · ") || "–"
  end

  def fin_sync_parts_columns
    cells = {
      "part" => ->(part) { fin_sync_part_label(part.part_key) },
      "status" => ->(part) { fin_sync_state(part.status, scope: :part) },
      "changes" => ->(part) { fin_sync_counts(part.counts) },
      "written" => ->(part) { fin_sync_stats(part.modified_rows) },
      "duration_ms" => ->(part) { fin_sync_ms(part.duration_ms) },
      "duration" => ->(part) { fin_sync_duration_muted(part.duration_ms) },
      "notices" => ->(part) { fin_sync_notice_counts(part.plan_object) }
    }
    Fin::SyncPartsColumns::COLUMNS.map { |col| col.to_table_column(cell: cells.fetch(col.key)) }
  end

  # One badge per level of the notices: how many records they name.
  def fin_sync_notice_counts(plan)
    by_level = plan.warnings.group_by(&:level)
    safe_join(Wsjrdp::Sync::Plan::LEVELS.filter_map do |level|
      notices = by_level[level] or next
      count = notices.sum { |notice| [notice.keys.size, 1].max }
      content_tag(:span, count, class: "badge #{NOTICE_BADGES.fetch(level)}",
        title: notices.map(&:message).join("\n"))
    end, " ")
  end

  # records: key (downcased) => its record (fin_sync_plan_records), a record
  # found is linked; model: the table the part writes.
  def fin_sync_changes_columns(records = {}, model = nil)
    cells = {
      "action" => ->(row) { t("fin.sync.action_names.#{row.change.action}") },
      "record" => ->(row) { fin_sync_change_record_link(row.change, fin_sync_row_record(row, records)) },
      "values" => ->(row) { fin_sync_target_chips(row, model) },
      "hints" => ->(row) { safe_join(row.notices.map { |notice| fin_sync_notice_badge(notice) }, " ") }
    }
    Fin::SyncChangesColumns::COLUMNS.map { |col| col.to_table_column(cell: cells.fetch(col.key)) }
  end

  # The record a row stands for: the one of its change, else the one its
  # change belongs to (the Moss user of a person).
  def fin_sync_row_record(row, records)
    records[row.change.key.to_s.downcase] || (row.change.ref && records[row.change.ref.to_s.downcase])
  end

  # Outlined, so they stand apart from the filled chips of the notices.
  TARGET_BADGES = {"new" => "border border-success text-success",
                   "changed" => "border border-primary text-primary",
                   "removed" => "border border-danger text-danger",
                   "unchanged" => "border text-muted"}.freeze

  # What a row writes, per model: "MossUser neu", "Person: 2 Felder neu",
  # "Person: 1 Feld geändert", ...
  def fin_sync_target_chips(row, model)
    chips = row.changes.flat_map { |change| fin_sync_change_chips(change, fin_sync_change_model_name(change, model)) }
    if fin_sync_ref_unchanged?(row)
      chips.unshift(fin_sync_target_badge("unchanged", t("fin.sync.targets.unchanged", model: model&.name)))
    end
    safe_join(chips, " ")
  end

  def fin_sync_change_chips(change, name)
    case change.action
    when "create" then [fin_sync_target_badge("new", t("fin.sync.targets.created", model: name))]
    when "restore" then [fin_sync_target_badge("new", t("fin.sync.targets.restored", model: name))]
    when "remove" then [fin_sync_target_badge("removed", t("fin.sync.targets.removed", model: name))]
    else
      change.values.values.group_by { |(old, new)| fin_sync_field_state(old, new) }
        .sort_by { |state, _| TARGET_BADGES.keys.index(state) }
        .map { |state, fields| fin_sync_target_badge(state, t("fin.sync.targets.fields_#{state}", model: name, count: fields.size)) }
    end
  end

  # A field of an update: newly set, changed or removed.
  def fin_sync_field_state(old, new)
    if old.blank? then "new"
    elsif new.blank? then "removed"
    else
      "changed"
    end
  end

  def fin_sync_target_badge(state, text) = content_tag(:span, text, class: "badge #{TARGET_BADGES.fetch(state)}")

  # A row of a change whose own record (ref) has no change: the person of a
  # Moss user that stays as it is.
  def fin_sync_ref_unchanged?(row) = row.change.ref.present? && row.related.empty?

  # The model a change writes: its target. A change stored before targets
  # existed has none: then the person key, else the part's model.
  def fin_sync_change_model(change, model)
    return fin_sync_target_class(change.target) if change.target

    fin_sync_legacy_person_change?(change) ? Person : model
  end

  def fin_sync_target_class(name)
    klass = name.safe_constantize
    klass if klass.is_a?(Class) && klass < ActiveRecord::Base
  end

  def fin_sync_change_model_name(change, model) = change.target || fin_sync_change_model(change, model)&.name || "?"

  # The jsonb column a change writes keys of, if any.
  def fin_sync_change_column(change)
    change.target ? change.target_column : ("additional_info" if fin_sync_legacy_person_change?(change))
  end

  def fin_sync_legacy_person_change?(change) = change.key.to_s.start_with?(Wsjrdp::Sync::MossApi::ListPart::PERSON_KEY)

  def fin_sync_notice_badge(notice)
    content_tag(:span, t("fin.sync.notice_labels.#{notice.code}"), class: "badge #{NOTICE_BADGES.fetch(notice.level, "text-bg-info")}")
  end

  def fin_sync_timings_columns(run)
    clock = ->(time) { fin_sync_clock(time, run.started_at) }
    bold = ->(row, text) { row.part ? text : content_tag(:strong, text) }
    cells = {
      "phase" => ->(row) { bold.call(row, safe_join([t("fin.sync.timings.phases.#{row.phase}"), fin_sync_failed(row)].compact, " ")) },
      "step" => ->(row) { bold.call(row, row.part ? fin_sync_part_label(row.part) : t("fin.sync.timings.run")) },
      "started_at" => ->(row) { clock.call(row.started_at) },
      "finished_at" => ->(row) { clock.call(row.finished_at) },
      "duration_ms" => ->(row) { fin_sync_ms(row.duration_ms) },
      "duration" => ->(row) { fin_sync_duration_muted(row.duration_ms) }
    }
    Fin::SyncTimingsColumns::COLUMNS.map { |col| col.to_table_column(cell: cells.fetch(col.key)) }
  end

  # The time of day; with the date when it is not the one of `day`. The full
  # date and time on hover.
  def fin_sync_clock(time, day)
    return if time.nil?

    same = time.in_time_zone.to_date == day.in_time_zone.to_date
    content_tag(:span, l(time.in_time_zone, format: same ? "%H:%M:%S" : "%d.%m.%Y %H:%M:%S"),
      title: fin_sync_time(time))
  end

  # A phase that did not succeed: its status as a badge, the error on hover.
  def fin_sync_failed(row)
    return if row.status.nil? || row.status == Wsjrdp::Sync::Timing::SUCCEEDED

    css = (row.status == Wsjrdp::Sync::Timing::FAILED) ? "text-bg-danger" : "text-bg-warning"
    content_tag(:span, t("fin.sync.timings.statuses.#{row.status}"), class: "badge #{css}", title: row.error_message)
  end

  # "13.054 ms"
  def fin_sync_ms(ms) = ms && "#{number_with_delimiter(ms, delimiter: ".")} ms"

  # The readable duration beside the milliseconds, muted.
  def fin_sync_duration_muted(ms) = content_tag(:span, fin_sync_duration_readable(ms), class: "text-muted fw-light")

  # "10,3 s" or "2 min 5 s"; nothing under a second (the milliseconds say it).
  def fin_sync_duration_readable(ms)
    return if ms.nil? || ms < 1000
    return fin_sync_seconds(ms) if ms < 60_000

    "#{ms / 60_000} min #{(ms % 60_000) / 1000} s"
  end

  def fin_sync_duration(ms)
    return "–" if ms.nil?

    (ms < 1000) ? "#{ms} ms" : fin_sync_seconds(ms)
  end

  # "10,3 s"
  def fin_sync_seconds(ms) = "#{format("%.1f", ms / 1000.0).tr(".", ",")} s"

  # {lower-case key => record} of the given keys: the rows of the part's table
  # by UUID and the people ("person:<id>"), one query each. A record not (yet)
  # in its table is missing.
  def fin_sync_records(part, keys)
    part_class = fin_sync_part_class(part)
    return {} unless part_class.respond_to?(:model) && keys.any?

    person_key = Wsjrdp::Sync::MossApi::ListPart::PERSON_KEY
    person_keys, uuids = keys.map { |key| key.to_s.downcase }.uniq.partition { |key| key.start_with?(person_key) }
    uuid_column = part_class.uuid_column
    records = part_class.model.where(uuid_column => uuids).index_by { |record| record[uuid_column].to_s.downcase }
    ids = person_keys.map { |key| key.delete_prefix(person_key).to_i }
    Person.where(id: ids).find_each { |person| records["#{person_key}#{person.id}"] = person } if ids.any?
    records
  end

  # One record of a notice: when it is in its table, its name as a link
  # (with the new-tab icon), then muted "Status: …" and for a Moss user
  # "E-Mail: …", then what the notice says of it ("→ <reference>"); else the
  # notice's own text.
  def fin_sync_notice_item(record, text)
    return text unless record

    path = polymorphic_path(record)
    return fin_sync_notice_person(record, path, text) if record.is_a?(Person)

    name = record.to_s
    email = record.try(:email).presence
    facts = [("Status: #{record.status}" if record.try(:status).present?),
      ("E-Mail: #{email}" if email && email != name)].compact
    rest = text.to_s.split(" → ", 2)[1]
    safe_join([safe_join([link_to(name, path), wsjrdp_newtab_link(path)]),
      (content_tag(:span, facts.join(" · "), class: "text-muted") if facts.any?), ("→ #{rest}" if rest)].compact, " ")
  end

  # A person of a notice: the name linked, then what the notice says of them.
  def fin_sync_notice_person(person, path, text)
    rest = text.to_s.split(" · ", 2)[1]
    safe_join([link_to(person.to_s, path), wsjrdp_newtab_link(path),
      (content_tag(:span, rest, class: "text-muted ms-1") if rest)].compact)
  end

  # The fields of a run (fin/sync_runs/_fields).
  def fin_format_wsjrdp_sync_run_source(run) = t("fin.sync.sources.#{run.source}", default: run.source)

  def fin_format_wsjrdp_sync_run_status(run) = fin_sync_state(run.status)

  def fin_format_wsjrdp_sync_run_selected_parts(run) = fin_sync_selected_parts(run.selected_parts)

  # "moss_api / wsjrdp_read · YAML", with the version when it is one.
  def fin_format_wsjrdp_sync_run_credential(run)
    return if run.account_key.blank?

    version = t("fin.sync.run.version", id: run.credential_id) if run.credential_id
    [[run.credential_kind, run.account_key].compact.join(" / "), run.credential_source, version].compact.join(" · ")
  end

  %i[started_at confirmed_at warnings_confirmed_at finished_at].each do |attr|
    define_method(:"fin_format_wsjrdp_sync_run_#{attr}") { |run| fin_sync_time(run.public_send(attr)) }
  end

  # "13.054 ms", then muted "13,1 s" from a second on.
  def fin_format_wsjrdp_sync_run_duration_ms(run)
    return unless run.duration_ms.positive?

    readable = fin_sync_duration_readable(run.duration_ms)
    safe_join([fin_sync_ms(run.duration_ms), (fin_sync_duration_muted(run.duration_ms) if readable)].compact, " ")
  end

  def fin_format_wsjrdp_sync_run_stats(run) = run.modified_rows.any? ? fin_sync_stats(run.modified_rows) : nil

  # The people the changes of a plan name (person_id), in one query.
  def fin_sync_people(plan)
    ids = plan.changes.flat_map { |change| Array(change.values["person_id"]) }.compact.uniq
    ids.empty? ? {} : Person.where(id: ids).index_by(&:id)
  end

  # The records a part's notices and changes (and their refs) are about.
  def fin_sync_plan_records(part, plan)
    keys = plan.warnings.flat_map(&:keys) + plan.changes.flat_map { |change| [change.key, change.ref].compact }
    fin_sync_records(part, keys)
  end

  # What a notice says of a change's record: its item for the change's key,
  # else for the record the change belongs to (ref).
  def fin_sync_notice_text(notice, change)
    keys = [change.key, change.ref].compact.map { |key| key.to_s.downcase }
    notice.items.find { |key, _| keys.include?(key.to_s.downcase) }&.last
  end

  # The label of a change, linked to its record when there is one.
  def fin_sync_change_record_link(change, record)
    return change.label unless record

    path = polymorphic_path(record)
    safe_join([link_to(change.label, path, data: {turbo_frame: "_top"}), wsjrdp_newtab_link(path)])
  end

  # The heading of a change's fields in its detail: the model, the record
  # (linked when there is one) and the table or column written.
  def fin_sync_change_heading(change, model, record)
    name = fin_sync_change_model_name(change, model)
    where = fin_sync_change_column(change) || model&.table_name
    label = record ? fin_sync_change_record_link(change, record) : change.label
    safe_join([name, label, (content_tag(:span, where, class: "text-muted") if where)].compact, " · ")
  end

  # A value of a change; a person id as a link to the person.
  def fin_sync_change_value(column, value, people)
    person = people[value] if column == "person_id"
    return fin_sync_value(value) unless person

    path = person_path(person)
    safe_join([link_to(person.to_s, path), wsjrdp_newtab_link(path),
      content_tag(:span, value, class: "text-muted ms-1")])
  end

  # A column of a change (Fin::SyncChangeRecord): the new value, or old → new,
  # then the chips of the notices about that column; labelled as on the
  # table's own pages, the column name as the label's tooltip.
  def fin_format_fields_of_fin_sync_change_record(record, column, _ctx)
    column = column.to_s
    value = record.change.values[column]
    parts = if record.create?
      [fin_sync_change_value(column, value, record.people)]
    else
      state = fin_sync_field_state(value.first, value.last)
      [(fin_sync_target_badge(state, t("fin.sync.targets.field_#{state}")) unless state == "changed"),
        fin_sync_change_value(column, value.first, record.people), "→",
        fin_sync_change_value(column, value.last, record.people)].compact
    end
    parts += record.notices(column).map { |notice| fin_sync_notice_badge(notice) }
    {value: safe_join(parts, " "), label: record.label(column), tooltip: column, blank: :empty}
  end

  # A value of a change as text.
  def fin_sync_value(value)
    case value
    when nil then content_tag(:span, "–", class: "text-muted")
    when Array then value.join(", ")
    else value.to_s
    end
  end
end
