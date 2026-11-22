# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# One version of one account of the credential store in one stage
# (doc/wsjrdp/credentials.md, "The table"). public_data holds the plain
# fields, secret_data each secret field sealed by itself with the version's
# one key. Write it through Wsjrdp::Credentials::Deposit, Change and Rekey;
# read it through Wsjrdp::Credentials.fetch.
#
# - What a row is here is its state (#examine), never an error.
# - Reading a field never depends on the column it lies in; writing one
#   (#write_field) removes it from the other column. The sealed value wins
#   over a plain one of the same name; a plain value is not authenticated.
# - The instants take a Time or nil only.
# - No sealed text reaches PaperTrail, inspect, the SQL log or as_json.
class WsjrdpCredential < ActiveRecord::Base
  # The states of #examine, in the order they are checked: whether the row
  # is this instance's, then its content, then its lifecycle -- so that a
  # planned version that will not open says so before its time comes.
  OTHER_STAGE = :other_stage       # a row of another stage
  KEY_MISSING = :key_missing       # this stage, sealed with a key this instance does not have
  KIND_UNKNOWN = :kind_unknown     # its kind is no longer in the registry
  # a sealed value does not open, the scheme is unknown, or the account key is no name
  UNREADABLE = :unreadable
  # it opens, but no longer fits its kind (also: a further field with a
  # name it cannot have)
  KIND_MISMATCH = :kind_mismatch
  REVOKED = :revoked               # revoked_at is reached
  EXPIRED = :expired               # expires_at is reached
  NOT_YET_VALID = :not_yet_valid   # valid_from lies ahead
  ACTIVE = Wsjrdp::Credentials::Lookup::USABLE # usable here

  # credential: whenever the values open and fit the kind, whatever the
  # state; warnings: the kind's warnings of those values (base_url:
  # not_https in production).
  Examination = Data.define(:state, :credential, :warnings) do
    def initialize(state:, credential:, warnings: [])
      super
    end
  end

  # Which fields a row holds, by name only, for a page. A list is nil when
  # it cannot be told here (unknown kind; for not_opening another stage, no
  # key or an unknown scheme). further: the fields the kind does not have.
  FieldReport = Data.define(:sealed, :plain, :in_both, :wrong_column, :further, :not_opening)

  FIXED_COLUMNS = %w[kind account_key stage author_id author_type created_at].freeze
  INSTANTS = %w[valid_from expires_at revoked_at].freeze
  # Fed by use, not by an admin: kept out of PaperTrail (reminded_at, a
  # datetime[], would be written there as a Ruby struct).
  HEALTH_COLUMNS = %w[last_success_at last_failure_at last_failure_message reminded_at].freeze
  UNTRAILED_COLUMNS = (%w[secret_data updated_at] + HEALTH_COLUMNS).freeze
  TRAIL_KEYS = %w[secret_fields_set secret_fields_changed secret_fields_resealed secret_fields_removed].freeze

  belongs_to :author, polymorphic: true, optional: true

  # PaperTrail records an update only when a column it does not skip
  # changed, so a change of secret fields alone gets its entry here.
  after_update :trail_secret_only_change

  # Around PaperTrail's before_destroy, so that #trail_data knows it is a
  # destroy -- only while it runs: a failed destroy leaves no mark.
  around_destroy :trail_destroy, prepend: true

  has_paper_trail on: %i[create update destroy], skip: UNTRAILED_COLUMNS,
    meta: {wsjrdp_data: ->(row) { row.trail_data }}

  # Also the key as given: a row written past the checks with a key not in
  # its one form is still found, and can be deleted.
  scope :of_account, lambda { |kind, account_key|
    key = account_key.to_s
    where(kind: kind.to_s, account_key: [key, Wsjrdp::Credentials.account_key_of(key)].uniq)
  }
  scope :newest_first, -> { order(created_at: :desc, id: :desc) }

  before_validation { self.comment ||= "" }
  # A new row's key in its one form; fixed once written.
  before_validation(on: :create) { self.account_key = Wsjrdp::Credentials.account_key_of(account_key) }

  # The registry a write path checks the kind against; Kinds.current by
  # default.
  attr_writer :kinds_registry

  validate :kind_known, on: :create
  validate :name_and_comment_text
  validate :scheme_known, on: :create
  validate :account_key_a_name
  validate :stage_a_stage
  validate :instants_given_as_instants
  validate :window_ordered
  validate :columns_of_values_well_formed
  validate :fixed_columns_unchanged, on: :update

  # as_json, to_json and to_xml leave secret_data out. attributes still
  # hand out everything: they are how the row is read, not a printed form.
  def serializable_hash(options = nil)
    options = options ? options.dup : {}
    options[:except] = Array(options[:except]).map(&:to_s) | ["secret_data"]
    options[:only] = Array(options[:only]).map(&:to_s) - ["secret_data"] if options[:only]
    options[:methods] = Array(options[:methods]).map(&:to_s) - ["secret_data"] if options[:methods]
    super
  end

  def reload(*)
    @instants_invalid = nil
    super
  end

  # A Time or nil only; anything else leaves the stored value and is
  # not_an_instant. The low-level write_attribute still parses a text, as
  # Rails does: the store does not use it for instants.
  INSTANTS.each do |attribute|
    define_method(:"#{attribute}=") { |value| write_instant(attribute, value) }
  end

  def state(**context) = examine(**context).state

  # Never raises for the row's content: whatever a row holds, it is one of
  # the states above.
  def examine(at: Time.current, keys: Wsjrdp::Credentials::Keys.current, kinds: Wsjrdp::Credentials::Kinds.current)
    return Examination.new(OTHER_STAGE, nil) unless stage == keys.stage
    return Examination.new(KEY_MISSING, nil) unless keys.accepted?(encryption_key_fingerprint)

    kind_object = kind_of(kinds)
    return Examination.new(KIND_UNKNOWN, nil) unless kind_object
    # A row written past the validations may hold anything.
    return Examination.new(UNREADABLE, nil) unless Wsjrdp::Credentials.account_key?(account_key)

    values = field_values(keys: keys)
    return Examination.new(UNREADABLE, nil) unless values

    # Only the kind's fields are cast; further fields are taken as they are.
    cast = kind_object.cast(values.select { |name, _value| kind_object.field?(name) }, stage: stage)
    further = values.reject { |name, _value| kind_object.field?(name) }
    return Examination.new(KIND_MISMATCH, nil) unless cast.valid? && further.keys.none? { |name| kind_object.further_name_problem(name) }

    Examination.new(lifecycle_state(at), credential_of(kind_object, cast.values.merge(further)), cast.warnings)
  end

  # {name => value} of every field, whichever column it lies in, further
  # fields included; nil when a sealed value does not open
  # here.
  def field_values(keys:)
    return nil unless scheme == Wsjrdp::Credentials::Sealer::SCHEME && values_columns_hashes?

    values, failing = readable_values(keys.find_by_fingerprint(encryption_key_fingerprint))
    failing.empty? ? values : nil
  end

  # [{name => value} of both columns, the sealed value winning over a plain
  # one of the same name; the names of the sealed values that do not open
  # with key (all of them without a key)]. A plain value never stands in
  # for a sealed one that does not open.
  def readable_values(key)
    opened, failing = key ? open_sealed_fields(key) : [{}, sealed_texts.keys]
    [plain_values.except(*failing).merge(opened), failing]
  end

  # [{name => value}, the names that do not open].
  def open_sealed_fields(key)
    opened = {}
    failing = []
    sealed_texts.each do |name, text|
      value = open_value(name, text, key)
      value.nil? ? failing << name : opened[name] = value
    end
    [opened, failing]
  end

  # ArgumentError unless each value is a Time (a TimeWithZone too) or nil;
  # the write paths take time objects only.
  def self.check_instants!(**instants)
    instants.each do |attribute, value|
      raise ArgumentError, "#{attribute} is not a Time or nil" unless value.nil? || value.is_a?(Time)
    end
  end

  # The two columns as hashes, {} where a column holds something else.
  def plain_values = public_data.is_a?(Hash) ? public_data : {}

  def sealed_texts = secret_data.is_a?(Hash) ? secret_data : {}

  # A row written past the validations may hold anything in them.
  def values_columns_hashes? = public_data.is_a?(Hash) && secret_data.is_a?(Hash)

  def sealed?(name) = sealed_texts.key?(name.to_s)

  def plain?(name) = plain_values.key?(name.to_s)

  # Whether the field lies only in the column it belongs to.
  def in_place?(name, secret:) = secret ? sealed?(name) && !plain?(name) : plain?(name) && !sealed?(name)

  # Into the column named, out of the other; nil removes the field. key
  # must be the version's own key (a version has one key), and both
  # columns must be hashes, else ArgumentError -- the write paths check
  # this first.
  def write_field(name, value, secret:, key: nil)
    name = name.to_s
    raise ArgumentError, "the field is not lower-case snake" unless Wsjrdp::Credentials.name?(name)
    raise ArgumentError, "a column of values is not a hash" unless values_columns_hashes?

    plain = plain_values.except(name)
    sealed = sealed_texts.except(name)
    if value.nil?
      # removed from both
    elsif secret
      sealed[name] = seal_value(name, value, key)
    else
      plain[name] = value
    end
    self.public_data = plain
    self.secret_data = sealed
  end

  # The wsjrdp_data of a PaperTrail version: the names of the secret
  # fields set, changed, re-sealed (a re-key) or removed. Names only.
  def trail_data
    before, after = trail_secret_change
    before = before.is_a?(Hash) ? before : {}
    after = after.is_a?(Hash) ? after : {}
    differing = (before.keys & after.keys).reject { |name| before[name] == after[name] }
    rekeyed = !@trail_destroying && saved_change_to_encryption_key_fingerprint?
    names = TRAIL_KEYS.zip([after.keys - before.keys, rekeyed ? [] : differing, rekeyed ? differing : [],
      before.keys - after.keys]).to_h
    names.reject { |_key, list| list.empty? }.transform_values { |list| shown(list).sort }
  end

  # Why the secret fields cannot be changed with these keys
  # (:unknown_scheme, :key_missing, :key_not_active), or nil.
  def secret_key_problem(keys)
    return :unknown_scheme unless scheme == Wsjrdp::Credentials::Sealer::SCHEME
    return :key_missing unless keys.accepted?(encryption_key_fingerprint)

    (keys.active&.fingerprint == encryption_key_fingerprint) ? nil : :key_not_active
  end

  def field_report(keys: Wsjrdp::Credentials::Keys.current, kinds: Wsjrdp::Credentials::Kinds.current)
    kind_object = kind_of(kinds)
    sealed = sealed_texts.keys
    plain = plain_values.keys
    FieldReport.new(sealed: shown(sealed), plain: shown(plain), in_both: shown(sealed & plain),
      wrong_column: kind_object && shown(wrong_column_names(kind_object, sealed, plain)),
      further: kind_object && shown((plain | sealed).reject { |name| kind_object.field?(name) }.sort),
      not_opening: not_opening_names(keys)&.then { |names| shown(names) })
  end

  private

  def kind_of(kinds) = kinds[kind]

  def shown(names) = names.map { |name| Wsjrdp::Credentials.shown_name(name) }

  def wrong_column_names(kind_object, sealed, plain)
    sealed.select { |name| kind_object.field(name)&.secret? == false } +
      plain.select { |name| kind_object.field(name)&.secret? }
  end

  def not_opening_names(keys)
    return nil unless stage == keys.stage && scheme == Wsjrdp::Credentials::Sealer::SCHEME

    key = keys.find_by_fingerprint(encryption_key_fingerprint)
    key && open_sealed_fields(key).last
  end

  def open_value(name, text, key)
    return nil unless [kind, name].all? { |part| Wsjrdp::Credentials.name?(part) }
    return nil unless Wsjrdp::Credentials.account_key?(account_key)
    return nil unless Wsjrdp::Credentials.stage?(stage)

    Wsjrdp::Credentials::Sealer.unseal(text, key: key, stage: stage, kind: kind, account_key: account_key, field: name)
  end

  def seal_value(name, value, key)
    unless key.is_a?(Wsjrdp::Credentials::Keys::Key) && key.fingerprint == encryption_key_fingerprint
      raise ArgumentError, "a secret field is sealed with the version's own key only"
    end

    Wsjrdp::Credentials::Sealer.seal(value, key: key, stage: stage, kind: kind, account_key: account_key, field: name)
  end

  def write_instant(attribute, value)
    @instants_invalid = (@instants_invalid || []) - [attribute]
    return @instants_invalid += [attribute] unless value.nil? || value.is_a?(Time)

    # To the microsecond the column keeps, so that a reload gives the same.
    self[attribute] = value&.change(usec: value.usec)
  end

  def lifecycle_state(at)
    if revoked_at && revoked_at <= at then REVOKED
    elsif expires_at && expires_at <= at then EXPIRED
    elsif valid_from && valid_from > at then NOT_YET_VALID
    else
      ACTIVE
    end
  end

  # A sealed further field counts as secret.
  def credential_of(kind_object, values)
    Wsjrdp::Credentials::Credential.new(kind: kind_object, account_key: account_key, stage: stage, values: values,
      key_fingerprint: encryption_key_fingerprint, version_name: name, version_id: id,
      secret_further_fields: values.keys.select { |name| !kind_object.field?(name) && sealed?(name) })
  end

  def trail_secret_change
    return [secret_data_in_database, {}] if @trail_destroying

    saved_change_to_secret_data || [secret_data, secret_data]
  end

  def trail_secret_only_change
    return unless saved_change_to_secret_data? && paper_trail_recording?
    return if (saved_changes.keys - paper_trail_options[:skip]).any? # PaperTrail's own callback recorded it

    attributes = {item: self, event: "update", whodunnit: PaperTrail.request.whodunnit, wsjrdp_data: trail_data}
    # controller_info, as PaperTrail merges it: mutation_id, whodunnit_type.
    PaperTrail::Version.create!(attributes.merge((PaperTrail.request.controller_info || {}).symbolize_keys))
  end

  def trail_destroy
    @trail_destroying = true
    yield
  ensure
    @trail_destroying = nil
  end

  def paper_trail_recording?
    PaperTrail.enabled? && PaperTrail.request.enabled? && PaperTrail.request.enabled_for_model?(self.class)
  end

  def kind_known
    return if kind_of(@kinds_registry || Wsjrdp::Credentials::Kinds.current)

    errors.add(:kind, :unknown_kind, message: "is not a kind of the registry")
  end

  def name_and_comment_text
    errors.add(:name, :not_valid_text, message: "is not valid text") unless name.nil? || Wsjrdp::Credentials.text?(name)
    return if Wsjrdp::Credentials.text?(comment)

    errors.add(:comment, :not_valid_text, message: "is not valid text")
  end

  def scheme_known
    return if scheme == Wsjrdp::Credentials::Sealer::SCHEME

    errors.add(:scheme, :unknown_scheme, message: "is not the scheme of the sealer")
  end

  def account_key_a_name
    return if Wsjrdp::Credentials.account_key?(account_key)

    errors.add(:account_key, :not_a_name, message: "is not of #{Wsjrdp::Credentials::ACCOUNT_KEY_RULE}")
  end

  def stage_a_stage
    return if Wsjrdp::Credentials.stage?(stage)

    errors.add(:stage, :not_a_stage, message: "is not of a-z and 0-9")
  end

  def instants_given_as_instants
    (@instants_invalid || []).each do |attribute|
      errors.add(attribute, :not_an_instant, message: "is not a time")
    end
  end

  def window_ordered
    return unless valid_from && expires_at && expires_at <= valid_from

    errors.add(:expires_at, :not_after_valid_from, message: "is not after valid_from")
  end

  # Checked only when the column changes, so that a row holding something
  # else can still change its other columns.
  def columns_of_values_well_formed
    if will_save_change_to_public_data? && !field_hash?(public_data) { |value| sealable_value?(value) }
      errors.add(:public_data, :not_field_values, message: "is not a hash of field names to values")
    end
    return unless will_save_change_to_secret_data? && !field_hash?(secret_data) { |text| text.is_a?(String) }

    errors.add(:secret_data, :not_field_values, message: "is not a hash of field names to sealed texts")
  end

  def field_hash?(data, &value_ok)
    data.is_a?(Hash) && data.all? { |name, value| Wsjrdp::Credentials.name?(name) && value_ok.call(value) }
  end

  def sealable_value?(value) = Wsjrdp::Credentials::Sealer.value_problem(value).nil?

  def fixed_columns_unchanged
    (changes_to_save.keys & FIXED_COLUMNS).each do |attribute|
      errors.add(attribute, :fixed, message: "is fixed once written")
    end
  end
end
