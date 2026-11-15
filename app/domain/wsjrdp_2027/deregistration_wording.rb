# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027
  # How a value of a deregistration is worded wherever a change of it is read
  # out: the Abmeldung page's flash (Person::DeregistrationController), the
  # person log of a deregistration row and the person log's older entries of
  # additional_info["deregistration_record"]
  # (Wsjrdp2027::PaperTrail::VersionDecorator). One place, so the three say it
  # the same way.
  #
  # A value is named by its key (KEYS) -- the person's accessor without the
  # deregistration_ prefix (#person_attr, #key).
  module DeregistrationWording
    # The values worded here, in the order the edit form asks for them -- and
    # the order a change is read in.
    KEYS = %w[
      kind
      reply_due_date
      effective_reply_due_date
      form_created_date
      receipt_created_date
      receipt_created_by_id
      refund_account_holder
      refund_iban
      refund_bic
      refund_sepa_address
      person_role
      person_role_name
      person_team_unit
      receipt_snapshot
      form_show_contractual_compensation
      refund_receipt_text
      refund_receipt_show_default_explanation
    ].freeze
    DATE_KEYS = %w[reply_due_date effective_reply_due_date form_created_date receipt_created_date].freeze
    # The two flags whose absent value means "shown".
    FLAGS = %w[form_show_contractual_compensation refund_receipt_show_default_explanation].freeze
    DEFAULT_KIND = "withdrawal"
    # What a change of one value reads like: U+2192 between the two, an en dash
    # where there is no value.
    CHANGE_ARROW = "→"
    BLANK_VALUE = "–"

    # A row's columns (WsjrdpDeregistration) as the change lines name them:
    # those worded here (row column => key), those read as they stand (row
    # column => the person's accessor), and the sub-keys of form_snapshot and
    # additional_info["refund_receipt"] (sub-key => key).
    ROW_COLUMN_KEYS = {
      "kind" => "kind", "reply_due_date" => "reply_due_date",
      "show_contractual_compensation" => "form_show_contractual_compensation"
    }.freeze
    ROW_PLAIN_COLUMNS = {
      "issue" => :deregistration_issue, "requested_date" => :deregistration_requested_date,
      "effective_date" => :deregistration_effective_date
    }.freeze
    ROW_SNAPSHOT_KEYS = {
      "created_date" => "form_created_date", "effective_reply_due_date" => "effective_reply_due_date",
      "refund_account_holder" => "refund_account_holder", "refund_iban" => "refund_iban",
      "refund_bic" => "refund_bic", "refund_sepa_address" => "refund_sepa_address",
      "person_role" => "person_role", "person_role_name" => "person_role_name",
      "person_team_unit" => "person_team_unit"
    }.freeze
    ROW_RECEIPT_KEYS = {
      "created_date" => "receipt_created_date", "created_by_id" => "receipt_created_by_id",
      "snapshot" => "receipt_snapshot", "text" => "refund_receipt_text",
      "show_default_explanation" => "refund_receipt_show_default_explanation"
    }.freeze
    # The documents and times of the row, each with its own wording
    # (people.deregistration.row_changes).
    ROW_DOCUMENT_COLUMNS = %w[sent_form_document_id signed_form_document_id].freeze
    ROW_TIME_COLUMNS = %w[form_sent_at signed_form_received_at].freeze

    module_function

    # One plain-text line per value a change of a row changed, in the words of
    # the Abmeldung page: {"column" => [before, after]} as PaperTrail's
    # changeset or an event's field_changes hold it. A value that reads as it
    # did has no line; columns in `except` and the row's bookkeeping (its id,
    # person, number, times) have none either. `eur` formats an amount in
    # euros (the helpers' format_eur_de).
    def row_change_lines(changes, except: [], eur: ->(value) { value.to_s })
      changes.to_h.flat_map do |attr, (from, to)|
        attr = attr.to_s
        next [] if except.include?(attr)

        if (key = ROW_COLUMN_KEYS[attr])
          same?(key, from, to) ? [] : [describe_change(key, from, to)]
        elsif (person_attr = ROW_PLAIN_COLUMNS[attr])
          [plain_change(person_attr, from, to)]
        elsif attr == "actual_compensation"
          [plain_change(:deregistration_actual_compensation_cents, from.presence && eur.call(from),
            to.presence && eur.call(to))]
        elsif attr == "status"
          [I18n.t("version.wsjrdp_deregistration_status", from: status_label(from), to: status_label(to))]
        elsif attr == "form_snapshot"
          hash_change_lines(ROW_SNAPSHOT_KEYS, from, to)
        elsif attr == "additional_info"
          receipt = WsjrdpDeregistration::RECEIPT_KEY
          hash_change_lines(ROW_RECEIPT_KEYS, hash_of(from)[receipt], hash_of(to)[receipt])
        elsif ROW_DOCUMENT_COLUMNS.include?(attr)
          [I18n.t("people.deregistration.row_changes.#{attr}", from: document_label(from), to: document_label(to))]
        elsif ROW_TIME_COLUMNS.include?(attr)
          [I18n.t("people.deregistration.row_changes.#{attr}", from: time_label(from), to: time_label(to))]
        else
          []
        end
      end
    end

    def plain_change(person_attr, from, to)
      "#{::Person.human_attribute_name(person_attr)}: #{plain_value(from)} #{CHANGE_ARROW} #{plain_value(to)}"
    end

    def plain_value(value)
      return BLANK_VALUE if value.blank?

      date = value.is_a?(Date) ? value : (Date.iso8601(value) if value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}\z/))
      date ? I18n.l(date) : value.to_s.squish
    end

    def hash_change_lines(keys, from, to)
      from = hash_of(from)
      to = hash_of(to)
      keys.filter_map do |sub_key, key|
        next if same?(key, from[sub_key], to[sub_key])

        describe_change(key, from[sub_key], to[sub_key])
      end
    end

    # A jsonb value as a Hash; a value stored as a JSON string is parsed.
    def hash_of(value)
      value = JSON.parse(value) if value.is_a?(String) && value.start_with?("{")
      value.is_a?(Hash) ? value.stringify_keys : {}
    rescue JSON::ParserError
      {}
    end

    def status_label(status)
      return BLANK_VALUE if status.blank?

      I18n.t("people.deregistration_statuses.#{status}", default: status.to_s)
    end

    def document_label(id) = id.present? ? I18n.t("people.deregistration.row_changes.document", id: id) : BLANK_VALUE

    def time_label(value)
      time = value.is_a?(String) ? Time.zone.iso8601(value) : value
      time ? I18n.l(time, format: "%d.%m.%Y %H:%M") : BLANK_VALUE
    rescue ArgumentError
      value.to_s
    end

    # The kind by its label, a flag as "anzeigen" or "ausblenden", a date
    # German, the receipt's figures as stored or not, its maker by name, any
    # other value as it stands -- and an en dash where there is nothing. A
    # missing value reads as the default the page shows for it.
    def describe(key, value)
      case key.to_s
      when "kind" then I18n.t("people.deregistration_kinds.#{value.presence || DEFAULT_KIND}")
      when *DATE_KEYS then value.present? ? I18n.l(value.to_date) : BLANK_VALUE
      when "receipt_snapshot"
        I18n.t("people.deregistration_record.#{value.present? ? "stored" : "not_stored"}")
      when "receipt_created_by_id" then value.present? ? (::Person.find_by(id: value)&.to_s || value.to_s) : BLANK_VALUE
      when *FLAGS then I18n.t("people.deregistration_form.#{shown?(value) ? "show" : "hide"}")
      else value.to_s.squish.presence || BLANK_VALUE
      end
    end

    # Whether two values read the same: a stored default and an absent value
    # do, so nothing that shows them as a change should.
    def same?(key, from, to) = describe(key, from) == describe(key, to)

    # The one line a change of one value reads as, label included.
    def describe_change(key, from, to)
      "#{::Person.human_attribute_name(person_attr(key))}: " \
        "#{describe(key, from)} #{CHANGE_ARROW} #{describe(key, to)}"
    end

    # What the person calls the value.
    def person_attr(key) = :"deregistration_#{key}"

    # Which key a person's accessor name stands for, nil for one not worded here.
    def key(person_attr)
      name = person_attr.to_s.delete_prefix("deregistration_")
      name if KEYS.include?(name)
    end

    # A flag as it is read: absent is "shown", and a value some other path
    # wrote as a string counts for what it says.
    def shown?(value)
      shown = ActiveModel::Type::Boolean.new.cast(value)
      shown.nil? || shown
    end
  end
end
