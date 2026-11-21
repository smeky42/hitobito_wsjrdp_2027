# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp::Credentials
  # The override by environment variables (doc/wsjrdp/credentials.md, "The
  # variables"): one version per account, from
  #
  #   HITOBITO_CREDENTIAL__<STAGE>__<KIND>__<ACCOUNT>__<FIELD>
  #   HITOBITO_CREDENTIAL__<STAGE>__<KIND>__<ACCOUNT>__NAME (or CREATED_AT, VALID_FROM, EXPIRES_AT)
  #
  # <ACCOUNT> is the account key in upper case, each of _ @ , . + - as _
  # (.account_part): foo@worldscoutjamboree.de is
  # FOO_WORLDSCOUTJAMBOREE_DE, a snake key keeps its form. Keys that map to
  # the same part (a.b, a-b, a_b) share its variables: they answer for
  # whichever key is asked for.
  #
  # Only the instance's own stage counts. Every variable of the prefix must
  # be understood: outside production a problem raises ConfigurationError;
  # production logs it and refuses the account it belongs to, or every
  # account when that cannot be told. Messages name the variable, never a
  # value.
  class Variables
    include Override::Source
    include Undumpable

    PREFIX = "HITOBITO_CREDENTIAL"
    OVERRIDE_PREFIX = "#{PREFIX}__".freeze
    PATTERN = "#{OVERRIDE_PREFIX}<STAGE>__<KIND>__<ACCOUNT>__<FIELD>".freeze
    SEPARATOR = "__"
    SOURCE = "variables"
    LABEL = "#{OVERRIDE_PREFIX}… variables".freeze
    # The parts beside the fields, as the keys of a version.
    META = Kinds::RESERVED_FIELD_NAMES
    SNAKE = "upper-case snake of at most #{NAME_LENGTH} characters".freeze
    # The four parts of a name, each with what it must be.
    ACCOUNT_PART = "an account key in upper case, _ between letters and digits"
    PARTS = [["stage", "of A-Z and 0-9"], ["kind", SNAKE], ["account key", ACCOUNT_PART], ["field", SNAKE]].freeze
    # What .account_part can give; upper case lengthens a key at most
    # threefold (ß is SS).
    ACCOUNT_PART_FORMAT = /\A[\p{L}0-9]+(?:_[\p{L}0-9]+)*\z/
    ACCOUNT_PART_LENGTH = ACCOUNT_KEY_LENGTH * 3
    # The rest of a name outside the grammar that a message may repeat.
    REST_FORMAT = /\A[A-Za-z0-9_]{0,#{NAME_LENGTH}}\z/
    UPPER_FORMAT = /\A[A-Z0-9_]+\z/

    attr_reader :stage, :accounts, :problems, :warnings

    # env: variable name => value; names outside the prefix are left alone.
    def initialize(env, stage:, kinds:)
      @stage = stage
      @kinds = kinds
      @problems = []
      @warnings = []
      # problem => the "kind/account key"s it refuses ([] when there is none
      # to refuse); a problem not in it is only ignored
      @refused = {}
      # [problem, [kind, account key] or nil] of the variables of this stage
      # that are not understood
      @broken = []
      entries = {}
      env.to_h.sort_by { |name, _value| name.to_s }.each { |name, value| read(name.to_s, value, entries) }
      resolve_broken(entries)
      @accounts = build(entries).freeze
      raise ConfigurationError, "#{LABEL} (stage #{shown_stage}): #{problems.join("; ")}" if problems.any? && !production?

      [@problems, @warnings, @refused].each(&:freeze)
      freeze
    end

    # The <ACCOUNT> part of the variables of an account key; the one place
    # that knows the rule.
    def self.account_part(account_key) = account_key.upcase.tr("@,.+-", "_")

    # A part that some account key gives: in upper case, and in lower case
    # an account key again (İ folds to i with a combining dot, which is none).
    def self.account_part?(part)
      part.is_a?(String) && part.length <= ACCOUNT_PART_LENGTH && ACCOUNT_PART_FORMAT.match?(part) &&
        part == part.upcase && Wsjrdp::Credentials.account_key?(Wsjrdp::Credentials.account_key_of(part))
    end

    def production? = stage == PRODUCTION

    # The account whose variables name the part of this key, under this
    # key. Accounts are held by the part in lower case.
    def account(kind, account_key)
      key = Wsjrdp::Credentials.account_key_of(account_key.to_s)
      return nil unless Wsjrdp::Credentials.account_key?(key)

      accounts[[kind.to_s, self.class.account_part(key).downcase]]&.for_key(key)
    end

    # The parts in lower case that are account keys themselves (DEFAULT is
    # default); for the list of accounts.
    def account_names = accounts.keys.select { |_kind, part| Wsjrdp::Credentials.account_key?(part) }

    def source_name = SOURCE

    def summary
      names = shown_account_names
      "#{LABEL}: stage #{shown_stage}, #{names.empty? ? "no override" : "overriding #{names.join(", ")}"}"
    end

    # Each problem (production only) with what became of it.
    def log_summary(logger)
      problems.each { |problem| logger.error("#{LABEL}: #{problem} -- #{outcome_of(problem)}") }
      warnings.each { |warning| logger.warn("#{LABEL}: #{warning} -- ignored") }
      logger.info(summary)
      self
    end

    def inspect
      "#<#{self.class.name} stage=#{shown_stage} accounts=#{shown_account_names.join(",")}>"
    end
    alias_method :to_s, :inspect

    def as_json(*)
      {"stage" => shown_stage, "accounts" => shown_account_names,
       "problems" => problems, "warnings" => warnings}
    end

    # The name as a message may show it: each part only when it is a name
    # (or a stage), else NOT_A_NAME -- a part may be a value in the wrong
    # place.
    def self.shown_variable(name)
      name = name.to_s.b.force_encoding(Encoding::UTF_8)
      return "#{PREFIX}#{NOT_A_NAME}" unless name.valid_encoding?
      unless name.start_with?(OVERRIDE_PREFIX)
        return REST_FORMAT.match?(name.delete_prefix(PREFIX)) ? name : "#{PREFIX}#{NOT_A_NAME}"
      end

      parts = name.delete_prefix(OVERRIDE_PREFIX).split(SEPARATOR, -1).each_with_index.map do |part, index|
        text = part.downcase
        shown = case index
        when 0 then Wsjrdp::Credentials.shown_stage(text, placeholder: nil)
        when 2 then account_part?(part)
        else Wsjrdp::Credentials.name?(text)
        end
        shown ? part : NOT_A_NAME
      end
      OVERRIDE_PREFIX + parts.join(SEPARATOR)
    end

    private

    attr_reader :kinds

    def outcome_of(problem)
      accounts = @refused[problem]
      if accounts.nil? then "the variable is ignored"
      elsif accounts.empty? then "the variable is ignored: the variables of stage #{shown_stage} name no account to refuse"
      else
        "refused, no version is used: #{accounts.join(", ")}"
      end
    end

    def shown_stage = Wsjrdp::Credentials.shown_stage(stage)

    # Adds one variable to its entry: the raw version (Override.read_version)
    # and, per key of it, the variable's name for the messages.
    def read(name, value, entries)
      # As bytes: under a C or POSIX locale Ruby tags ENV strings US-ASCII.
      name = name.b.force_encoding(Encoding::UTF_8)
      return unless name.start_with?(PREFIX)
      return if [Keys::ENV_NAME, Keys::LABEL_ENV_NAME].include?(name)

      shown = self.class.shown_variable(name)
      # May belong to any account of this stage.
      return @broken << ["#{shown}: the name is not valid text", nil] unless name.valid_encoding?

      parts = parts_of(name, shown)
      return unless parts

      variable_stage, kind_name, account_key, part = parts
      return unless own_stage?(variable_stage, shown)

      kind = kinds[kind_name]
      return @broken << ["#{shown}: no kind #{kind_name} in #{kinds.source}", nil] unless kind

      entry = entry_of(entries, kind, account_key)
      meta = META.include?(part)
      (meta ? entry[:raw] : entry[:raw]["vars"])[part] = value.to_s.b.force_encoding(Encoding::UTF_8)
      entry[:names][meta ? part : "vars.#{part}"] = shown
    end

    # The four parts in lower case, or nil after recording the problem. A
    # name outside the grammar is broken when, after the prefix and its
    # underscores, it begins with this stage, whatever the case (a missing
    # underscore of the prefix too); else it refuses no account. A typo in
    # the stage itself cannot be caught.
    def parts_of(name, shown)
      if name.start_with?(OVERRIDE_PREFIX)
        parts = name.delete_prefix(OVERRIDE_PREFIX).split(SEPARATOR, -1)
        problem = parts_problem(parts)
        return parts.map(&:downcase) unless problem
      else
        problem = "not a variable of the credential store (#{PATTERN}, #{Keys::ENV_NAME}, #{Keys::LABEL_ENV_NAME})"
      end

      message = "#{shown}: #{problem}"
      rest = name.delete_prefix(PREFIX).sub(/\A_+/, "")
      rest.downcase.start_with?(stage) ? @broken << [message, loose_key(rest.split(SEPARATOR, -1))] : problems << message
      nil
    end

    def parts_problem(parts)
      return "not of the form #{PATTERN}" unless parts.size == PARTS.size

      upper = parts.each_with_index.all? do |part, index|
        (index == 2) ? /\A[\p{L}0-9_]+\z/.match?(part) && part == part.upcase : UPPER_FORMAT.match?(part)
      end
      return "a part is not in upper case (A-Z, 0-9 and _; letters of any script in the account)" unless upper

      PARTS.zip(parts).each_with_index do |((what, rule), part), index|
        valid = case index
        when 0 then UPPER_FORMAT.match?(part) && Wsjrdp::Credentials.stage?(part.downcase)
        when 2 then self.class.account_part?(part)
        else UPPER_FORMAT.match?(part) && Wsjrdp::Credentials.name?(part.downcase)
        end
        return "the #{what} is not #{rule}" unless valid
      end
      nil
    end

    # The [kind, account key] that a name outside the grammar surely names:
    # its first three parts, case folded, are this stage, a kind and an
    # account key, and a further part follows. In a name of three parts the
    # third may be the account and the field joined
    # (MOSS_API__DEFAULT_EXPIRES_AT).
    def loose_key(parts)
      return nil if parts.size < 4

      variable_stage, kind_name = parts.first(2).map(&:downcase)
      part = parts[2].upcase
      return nil unless variable_stage == stage && kinds[kind_name] && self.class.account_part?(part)

      [kind_name, part.downcase]
    end

    # A broken variable refuses the account it surely names, whether or not
    # another variable names it. One that names none may belong to any
    # account, so it refuses every account of the variables (a guess would
    # always miss a case).
    def resolve_broken(entries)
      unplaced = []
      @broken.each do |problem, key|
        key ? refuse(entry_of(entries, kinds[key.first], key.last), problem) : unplaced << problem
      end
      unplaced.each do |problem|
        problems << problem
        @refused[problem] = entries.keys.map { |pair| pair.join("/") }.sort
      end
      entries.each_value { |entry| entry[:refused] = true } if unplaced.any?
    end

    def entry_of(entries, kind, account_key)
      entries[[kind.name, account_key]] ||= {kind: kind, account_key: account_key, raw: {"vars" => {}}, names: {},
                                             refused: false}
    end

    # A PRODUCTION variable outside production is a problem, any other
    # stage a warning.
    def own_stage?(variable_stage, shown)
      return true if variable_stage == stage

      if variable_stage == PRODUCTION
        problems << "#{shown}: a production variable outside production (stage #{shown_stage})"
      else
        shown_other = Wsjrdp::Credentials.shown_stage(variable_stage, placeholder: nil)
        warnings << "#{shown} belongs to #{shown_other ? "stage #{shown_other}" : "another stage"}, " \
          "this is #{shown_stage}"
      end
      false
    end

    def refuse(entry, problem)
      entry[:refused] = true
      problems << problem
      (@refused[problem] ||= []) << "#{entry[:kind].name}/#{entry[:account_key]}"
    end

    def build(entries)
      entries.to_h do |(kind_name, account_key), entry|
        version = Override.read_version(entry[:raw], kind: entry[:kind], position: 1) do |key, message|
          refuse(entry, "#{entry[:names].fetch(key)}: #{message}")
        end
        account = Override::Account.new(kind: entry[:kind], account_key: account_key, versions: [version],
          refused: entry[:refused])
        [[kind_name, account_key], account]
      end
    end
  end
end
