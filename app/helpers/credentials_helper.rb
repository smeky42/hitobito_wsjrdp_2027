# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "digest"

# The credential store pages: states, times, fields and the change
# history. Nothing here puts a secret value into the page: a hidden field
# shows dots and a short fingerprint, and its value comes only through
# the reveal button (Wsjrdp::Credentials::Reveal).
module CredentialsHelper
  I18N = "credentials"
  MASK = "••••••••"
  # One character an account key may hold.
  ACCOUNT_KEY_CHARACTER = /\A(?:#{Wsjrdp::Credentials::ACCOUNT_KEY_LETTER}|[0-9_@,.+-])\z/
  SOURCE_MARKS = {"variables" => "ENV", "file" => "YAML"}.freeze
  STATE_CLASSES = {active: "success", not_yet_valid: "info", expired: "secondary", revoked: "secondary",
                   other_stage: "secondary"}.freeze
  # The columns a change of a version names in the trail, with their values.
  TRAIL_ATTRIBUTES = %w[name comment valid_from expires_at revoked_at encryption_key_fingerprint].freeze
  # A trail value longer than this is cut, all of it on hover.
  TRAIL_VALUE_LENGTH = 80
  # An account key that looks like a token or a secret. Keep in sync with
  # credentials/_new_js.
  ACCOUNT_KEY_TOKEN = /\h{32,}|(?=[\p{L}0-9]*[0-9])(?=[\p{L}0-9]*\p{L})[\p{L}0-9]{20,}|\h{8}-\h{4}-\h{4}-\h{4}-\h{12}/

  # One field of a version as the page shows it. value: a public value;
  # fingerprint: a short tag of a hidden value; revealable: whether the
  # reveal button is offered; further: a field the kind does not have.
  FieldRow = Data.define(:name, :set, :masked, :value, :fingerprint, :revealable, :further)

  def credential_kind_label(name) = t("#{I18N}.kinds.#{name}", default: credential_name(name))

  # A kind, an account key or a field as the page shows it: only a valid
  # name. Anything else may be a secret typed into the wrong place.
  def credential_name(value) = Wsjrdp::Credentials.shown_name(value, placeholder: t("#{I18N}.invalid"))

  def credential_account_key(value) = Wsjrdp::Credentials.shown_account_key(value, placeholder: t("#{I18N}.invalid"))

  def credential_stage(value) = Wsjrdp::Credentials.shown_stage(value, placeholder: t("#{I18N}.invalid"))

  # Why a typed account key is not valid, one line each; [] if it is.
  def credential_account_key_problems(given)
    key = Wsjrdp::Credentials.account_key_of(given.to_s)
    return [] unless Wsjrdp::Credentials.text?(key) && !Wsjrdp::Credentials.account_key?(key)

    scope = "#{I18N}.new.problems"
    bad = key.each_char.reject { |char| ACCOUNT_KEY_CHARACTER.match?(char) }.uniq
    problems = []
    problems << t("#{scope}.not_allowed", chars: bad.map { |char| credential_character(char) }.join(", ")) if bad.any?
    problems << t("#{scope}.edge") if /\A[_@,.+-]|[_@,.+-]\z/.match?(key)
    problems << t("#{scope}.row") if /[_@,.+-]{2}/.match?(key)
    problems << t("#{scope}.too_long", length: Wsjrdp::Credentials::ACCOUNT_KEY_LENGTH) if key.length > Wsjrdp::Credentials::ACCOUNT_KEY_LENGTH
    problems
  end

  # Hints, not problems, for a typed account key: it looks like a token,
  # or holds letters beyond ASCII.
  def credential_account_key_warnings(given)
    key = Wsjrdp::Credentials.account_key_of(given.to_s)
    return [] unless Wsjrdp::Credentials.text?(key)

    scope = "#{I18N}.new.warnings"
    [(t("#{scope}.token") if ACCOUNT_KEY_TOKEN.match?(key)),
      (t("#{scope}.non_ascii") if !key.ascii_only? && Wsjrdp::Credentials.account_key?(key))].compact
  end

  # The existing accounts by kind and variable name, for the warning that
  # a new key would share their variables.
  def credential_account_parts(overview)
    overview.account_names.each_with_object({}) do |(kind, key), parts|
      next unless Wsjrdp::Credentials.account_key?(key)

      ((parts[kind] ||= {})[Wsjrdp::Credentials::Variables.account_part(key)] ||= []) << key
    end
  end

  # The title of an account's page and its forms: kind, display name and
  # account key. Plain text: the page escapes it.
  def credential_account_title(kind_name, account_key, name: nil)
    key = credential_account_key(account_key)
    "#{credential_kind_label(kind_name)} · #{name.present? ? "#{name} (#{key})" : key}"
  end

  # The display name of an account: that of the version in use, else the
  # first one found.
  def credential_display_name(report)
    credential_versions_in_order(report).map(&:name).find(&:present?)
  end

  def credential_source_mark(source) = SOURCE_MARKS[source]

  def credential_source_label(source) = t("#{I18N}.sources.#{source}")

  # Who added a version: a person or a service token, linked when the
  # viewer may see it.
  def credential_author(author)
    name = author&.to_s.presence || "–"
    path = case author
    when Person then person_path(author) if can?(:show, author)
    when ServiceToken then group_service_token_path(author.layer_group_id, author) if can?(:show, author)
    end
    path ? link_to(name, path) : name
  end

  # A time in UTC, then in the app's time zone if that differs and
  # local is true. A muted "not set" when there is none.
  def credential_instant(time, local: true)
    return content_tag(:span, t("#{I18N}.version.not_set"), class: "text-muted") unless time

    utc = l(time.getutc, format: "%d.%m.%Y %H:%M UTC")
    return utc if !local || Wsjrdp::InstantInput::UTC_ZONES.include?(Time.zone.tzinfo.identifier)

    safe_join([utc, " · ", content_tag(:span, l(time.in_time_zone, format: "%d.%m.%Y %H:%M %Z"), class: "text-muted")])
  end

  # The state label of a version, such as active, planned or expired.
  def credential_state_label(version)
    return t("#{I18N}.states.#{version.state}", default: version.state.to_s) unless version.state == :not_yet_valid

    t("#{I18N}.states.not_yet_valid_html", time: credential_instant(version.valid_from, local: false))
  end

  # The versions of an account in page order: the one in use first, then
  # the others by source, versions of another stage last.
  def credential_versions_in_order(report)
    report.versions.each_with_index.sort_by do |version, index|
      rank = if version.role == Wsjrdp::Credentials::Overview::ACTIVE then 0
      elsif version.state == WsjrdpCredential::OTHER_STAGE then 2
      else
        1
      end
      [rank, index]
    end.map(&:first)
  end

  # For each source below the one in use: the version that would be in use
  # without the override.
  def credential_overridden_versions(report)
    report.versions.select(&:overridden_by).group_by(&:source).values
      .filter_map { |versions| versions.find { |version| version.state == Wsjrdp::Credentials::Lookup::USABLE } }
  end

  # The source label (DB, ENV or YAML) and its tooltip.
  def credential_source_chip(version)
    mark = credential_source_mark(version.source) || "DB"
    [mark, t("#{I18N}.chips.source.#{version.source}", source: overview.file.source)]
  end

  def credential_state_class(version)
    return "secondary" if version.overridden_by

    STATE_CLASSES.fetch(version.state, "danger")
  end

  # The start of a key's fingerprint; all of it on hover.
  def credential_fingerprint(fingerprint)
    return "–" if fingerprint.blank?

    content_tag(:span, "#{fingerprint.to_s[0, 8]}…", class: "font-monospace", title: fingerprint)
  end

  # A short hash of a value, stored nowhere. Never show more of it: the
  # full hash of a weak secret could be guessed back.
  def credential_value_fingerprint(value)
    content_tag(:span, "#{Digest::SHA256.hexdigest(value.to_s)[0, 4]}…", class: "font-monospace")
  end

  # When the row was last changed, sent with the edit form to detect a
  # change made in between.
  def credential_lock(row) = row.updated_at&.utc&.iso8601(6).to_s

  def credential_key_active?(row, keys) = keys.active&.fingerprint == row.encryption_key_fingerprint

  # Re-keying helps only if the row's key is known here but not the
  # active one.
  def credential_rekey?(row, keys) = row.secret_key_problem(keys) == :key_not_active

  # One sentence per problem.
  def credential_problems_text(problems) = problems.map { |problem| credential_problem_message(problem) }.join(" ")

  def credential_problem_message(problem)
    field = problem.field.to_s
    label = t("#{I18N}.attributes.#{field}", default: field)
    t("#{I18N}.codes.#{problem.code}", field: label, default: t("#{I18N}.codes.other", field: label, code: problem.code))
  end

  def credential_problems_of(problems, field) = problems.select { |problem| problem.field.to_s == field.to_s }

  # The fields of a version: the kind's first, then the further fields.
  def credential_field_rows(version, kind, keys)
    if version.record
      credential_database_field_rows(version.record, kind, keys)
    else
      credential_override_field_rows(version.credential, kind)
    end
  end

  # The decrypted values of a database row of this stage, else nil.
  def credential_row_values(row, keys) = (row.stage == keys.stage) ? row.field_values(keys: keys) : nil

  # Hints about a row's fields: in the wrong column, or not decryptable.
  def credential_field_hints(row, keys, kinds)
    report = row.field_report(keys: keys, kinds: kinds)
    %i[wrong_column not_opening].flat_map do |list|
      Array(report.public_send(list)).map { |name| t("#{I18N}.field_report.#{list}", field: name) }
    end
  end

  # Shown under the account key in the list: the title field of the
  # version in use, never a hidden one; nil if there is none.
  def credential_title_value(report, kind)
    in_use = credential_active_version(report)
    field = kind&.title_field && kind.field(kind.title_field)
    return nil unless in_use && field && !Wsjrdp::Credentials::Reveal.masked?(field.name, kind: kind, record: in_use.record)
    return nil unless in_use.credential.field_names.include?(field.name)

    in_use.credential[field.name].to_s
  end

  # The other stages that have database rows, with their counts.
  def credential_other_stages(report)
    report.versions.select { |version| version.state == WsjrdpCredential::OTHER_STAGE }
      .group_by { |version| credential_stage(version.record.stage) }.transform_values(&:size)
  end

  # The account's state here, for the list.
  def credential_account_state(report)
    in_use = credential_active_version(report)
    return t("#{I18N}.list.no_active_version") unless in_use

    parts = [t("#{I18N}.states.active")]
    if in_use.expires_at && in_use.expires_at - Time.current <= 30.days
      parts << t("#{I18N}.list.expires_html", time: credential_instant(in_use.expires_at))
    end
    safe_join(parts, " · ")
  end

  # The change history of a row, newest first.
  def credential_trail(row)
    PaperTrail::Version.where(item_type: WsjrdpCredential.name, item_id: row.id).order(created_at: :desc, id: :desc)
  end

  # Who made a history entry, linked like the author of a version.
  def credential_trail_author(version)
    who = version.whodunnit
    model = {Person.name => Person, ServiceToken.name => ServiceToken}[version.whodunnit_type]
    return who.to_s if who.blank? || model.nil?

    author = model.find_by(id: who)
    author ? credential_author(author) : "#{model.model_name.human} #{who}"
  end

  # What a history entry did, in short. Public values are shown; a hidden
  # field is named only, never with its value.
  def credential_trail_text(version, row)
    data = version.wsjrdp_data.is_a?(Hash) ? version.wsjrdp_data : {}
    parts = [t("#{I18N}.trail.events.#{version.event}", default: version.event.to_s)]
    parts.concat(credential_trail_changes(version, row)) unless version.event == "destroy"
    WsjrdpCredential::TRAIL_KEYS.each do |key|
      names = Array(data[key])
      parts << t("#{I18N}.trail.#{key}", fields: names.join(", ")) if names.any?
    end
    safe_join(parts, " · ")
  end

  private

  # A character as a message names it; a space or an invisible character
  # by name or code point.
  def credential_character(char)
    return t("#{I18N}.new.problems.space") if char == " "

    /[\p{C}\p{Z}\p{M}]/.match?(char) ? format("U+%04X", char.ord) : "„#{char}“"
  end

  # The version in use of an account, or nil.
  def credential_active_version(report)
    report.versions.find { |version| version.role == Wsjrdp::Credentials::Overview::ACTIVE }
  end

  def credential_database_field_rows(row, kind, keys)
    values = credential_row_values(row, keys)
    kind_names = kind ? kind.field_names : []
    names = kind_names | (row.sealed_texts.keys | row.plain_values.keys).sort_by(&:to_s)
    reveal = Wsjrdp::Credentials::Reveal.enabled?
    names.map do |name|
      masked = Wsjrdp::Credentials::Reveal.masked?(name, kind: kind, record: row)
      opened = values&.key?(name)
      set = values ? opened : row.sealed?(name) || row.plain?(name)
      value = (values || row.plain_values)[name] unless masked
      FieldRow.new(name: credential_name(name), set: set, masked: masked, value: value,
        fingerprint: (masked && opened) ? credential_value_fingerprint(values[name]) : nil,
        revealable: masked && opened && reveal && Wsjrdp::Credentials.name?(name),
        further: !kind.nil? && !kind_names.include?(name))
    end
  end

  def credential_override_field_rows(credential, kind)
    return [] unless credential && kind

    reveal = Wsjrdp::Credentials::Reveal.enabled?
    rows = kind.fields.map do |field|
      set = credential.field_names.include?(field.name)
      value = (field.secret? ? credential.secret(field.name) : credential[field.name]) if set
      FieldRow.new(name: field.name, set: set, masked: field.secret?, value: field.secret? ? nil : value,
        fingerprint: (set && field.secret?) ? credential_value_fingerprint(value) : nil,
        revealable: set && field.secret? && reveal, further: false)
    end
    # An override's further fields are public; hidden anyway if one is not.
    rows + credential.further_field_names.map do |name|
      secret = credential.secret_field?(name)
      FieldRow.new(name: name, set: true, masked: secret, value: secret ? nil : credential[name],
        fingerprint: secret ? credential_value_fingerprint(credential.secret(name)) : nil, revealable: false,
        further: true)
    end
  end

  def credential_trail_changes(version, row)
    changes = begin
      version.changeset
    rescue StandardError
      {}
    end
    created = version.event == "create"
    parts = (changes.keys & TRAIL_ATTRIBUTES).filter_map do |attribute|
      from, to = changes[attribute]
      next if created && to.blank?

      label = t("#{I18N}.attributes.#{attribute}")
      to_text = credential_trail_value(attribute, to)
      created ? safe_join([label, ": ", to_text]) : safe_join([label, ": ", credential_trail_value(attribute, from), " → ", to_text])
    end
    parts + credential_trail_public_fields(changes["public_data"], row, created)
  end

  def credential_trail_value(attribute, value)
    return "–" if value.blank?
    return credential_instant(value) if value.is_a?(Time)
    return credential_fingerprint(value) if attribute == "encryption_key_fingerprint"

    safe_join(["„", credential_trail_short(value), "“"])
  end

  # A long value shortened, all of it on hover; only for values that are
  # not secret.
  def credential_trail_short(value)
    text = value.to_s
    return text if text.length <= TRAIL_VALUE_LENGTH

    content_tag(:span, "#{text[0, TRAIL_VALUE_LENGTH]}…", title: text)
  end

  # The public fields of a history entry with their values; a field that
  # may be secret by name only.
  def credential_trail_public_fields(change, row, created)
    from, to = Array(change)
    from = from.is_a?(Hash) ? from : {}
    to = to.is_a?(Hash) ? to : {}
    kind = Wsjrdp::Credentials::Kinds.current[row.kind]
    named = []
    shown = []
    (from.keys | to.keys).reject { |name| from[name] == to[name] }.each do |name|
      if Wsjrdp::Credentials::Reveal.masked?(name, kind: kind, record: row)
        named << credential_name(name)
      else
        shown << credential_trail_field(name, from, to, created)
      end
    end
    parts = []
    parts << safe_join([t("#{I18N}.trail.public_fields_set"), " ", safe_join(shown, ", ")]) if created && shown.any?
    parts.concat(shown) unless created
    parts << t("#{I18N}.trail.#{created ? "public_fields_named" : "public_fields"}", fields: named.join(", ")) if named.any?
    parts
  end

  def credential_trail_field(name, from, to, created)
    return safe_join([name, " = ", credential_trail_short(to[name])]) if created
    return t("#{I18N}.trail.field_added_html", field: name, value: credential_trail_short(to[name])) unless from.key?(name)
    return t("#{I18N}.trail.field_removed_html", field: name, value: credential_trail_short(from[name])) unless to.key?(name)

    safe_join([name, ": „", credential_trail_short(from[name]), "“ → „", credential_trail_short(to[name]), "“"])
  end
end
