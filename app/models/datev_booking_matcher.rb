# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Proposes and writes links between DATEV bookings and their Beitragsbuchung
# (accounting entry). See doc/bookkeeping_schema_review.md §3c.
#
# Every proposal requires the EXACT amount INCLUDING THE SIGN -- the
# booking's signed amount seen from the fee account (41030) side must equal
# the entry's amount_cents -- and an entry not yet linked to any booking.
# Channels:
#
#   * Ende-zu-Ende-ID (score 100): Belegfeld 1 "Einzug-..-<id>" resolves via
#     the pre-notification id to exactly one entry whose person also appears
#     in the Buchungstext (silent safety check).
#   * Scored person/date matching: the best-scoring entry wins; the top
#     candidates are kept as alternatives (shown in the detail view). Score =
#     person-match % x date-match %:
#       person 100  booking.person_id already set (counts as full name match)
#       person 100  person id WITH role prefix (TN/CMT/YP/UL/IST) in the text
#       person 100  short full name (first word of first name + last name) in
#                   the text
#       person  85  full name SIMILAR (small typos, e.g. "Mustremann" for
#                   "Mustermann", "Beisiel" for "Beispiel")
#       person  80  an ALTERNATIVE full name in the text: Person.sepa_name
#                   (account holder) or additional_contact_name_a/b -- e.g. a
#                   parent with a different surname paying the fee
#       person  70  only the last name in the text
#       person  65  alternative name SIMILAR (typo tolerance per word)
#       person  60  last name similar, or person id WITHOUT prefix in the text
#       person  40  only the first name in the text (low confidence)
#       person  30  only the first name similar (very low confidence)
#       date   100  entry value_date OR entry booking_date = booking date,
#                   OR a shared Jira-style reference code (e.g. HELP-1234)
#                   in both texts -- date-independent (refunds are often
#                   booked weeks after the payout; such entries join the
#                   candidate pool regardless of their dates)
#       date    70  one of them within +-7 days
#       date    40  one of them within +-92 days (~three months); beyond
#                   that a pair is NEVER a candidate (except via a shared
#                   reference code)
#     score 100 => :sure (green), below => :heuristic (yellow). Ties on the
#     best score are ambiguous: NO proposal, but the tied candidates appear as
#     alternatives for manual review.
#
# connect!/connect_pair! write accounting_entry_id, person_id AND
# camt_transaction_id (mirrored from the entry) in ONE bulk UPDATE.
module DatevBookingMatcher
  EINZUG_DF1 = /\AEinzug-\d{4}-\d{2}-\w+-\d+-(\d+)\z/
  PREFIXED_PERSON_ID = /\b(?:TN|CMT|YP|UL|IST)\s+(\d+)\b/
  # Jira-style reference codes (e.g. "HELP-1234") shared between the booking
  # text and the entry description identify the pair regardless of how far
  # the dates are apart (refunds are often booked weeks after the payout).
  REFERENCE_CODE = /\b[A-Za-z]{2,10}-\d{2,6}\b/
  DATE_WINDOW = 7 # days
  WIDE_DATE_WINDOW = 92 # days (~three months): beyond this, never a candidate
  MAX_ALTERNATIVES = 5
  FEE_ACCOUNT = "41030" # TN-Beiträge (Ertrag)
  # A same-amount candidate group larger than this is narrowed to entries whose
  # person is actually named (id / prefixed id / exact last name) in the text
  # before scoring: a heuristic match hidden among thousands of same-amount
  # rows would be ambiguous anyway, and the all-pairs scoring would dominate the
  # runtime (mostly relevant when reconciling a fully-unlinked dataset).
  BIG_AMOUNT_GROUP = 150

  # THE one place the heuristic middle/low boundary lives (a code-only knob, not
  # user-adjustable, see doc/recon_linking.md): a computed rating STRICTLY GREATER
  # than this percentage is :heuristic_middle, this value or below is
  # :heuristic_low. Used by Match#tier.
  HEURISTIC_MIDDLE_MIN_PERCENT = 50

  # One proposed link. score: 0..100. kind distinguishes HOW the pair was
  # found -- and that, not the score, drives the confidence level:
  #
  #   :import    the DATEV import itself would create this exact link. Two
  #              rules qualify, both mirroring the importer: the
  #              Ende-zu-Ende-ID channel (Belegfeld 1 -> pre-notification),
  #              and -- for 2025 bookings -- the person id with its role prefix
  #              in the Buchungstext plus the entry's Valuta exactly on the
  #              booking date (see import_equivalent_2025?). level :sure --
  #              shown green.
  #   :heuristic a scored person/date/initials guess. level :heuristic --
  #              shown amber EVEN AT score 100: a heuristic full hit is still a
  #              heuristic, not something the import would have produced.
  #
  # basis: short explanation for the table cell; details: multi-line
  # explanation for the hover tooltip; person_name: display name of the
  # entry's person. A Match links an `entry` and a `booking`; the FORWARD
  # direction (propose) fills `entry` (the proposed Beitragsbuchung for a
  # booking), the REVERSE direction (propose_for_entries) fills `booking` (the
  # proposed DATEV booking for an entry). Same score/kind/level/colours both
  # ways.
  Match = Struct.new(:entry, :booking, :score, :basis, :details, :person_name, :kind, keyword_init: true) do
    # Two-value confidence kept for the connect-controls / atom logic.
    def level = (kind == :import) ? :sure : :heuristic

    # Four-tier confidence for DISPLAY (see doc/recon_linking.md):
    #   :automatic        a link the DATEV import itself would create -- the
    #                     2025 fee rule or the Ende-zu-Ende-ID (Einzug) channel
    #                     (kind :import). Always 100 %.
    #   :heuristic_high   computed score 100 %
    #   :heuristic_middle computed score OVER HEURISTIC_MIDDLE_MIN_PERCENT
    #   :heuristic_low    computed score at/below that threshold
    def tier
      return :automatic if kind == :import
      return :heuristic_high if score >= 100
      return :heuristic_middle if score > HEURISTIC_MIDDLE_MIN_PERCENT
      :heuristic_low
    end
  end

  # propose result: proposals = {booking_id => Match} (unique best);
  # alternatives = {booking_id => [Match, ...]} (top candidates by score, only
  # for bookings WITHOUT a sure proposal -- including ambiguous ones that got
  # no proposal at all).
  Result = Struct.new(:proposals, :alternatives, keyword_init: true)

  def self.propose(bookings)
    bookings = bookings.to_a.reject(&:accounting_entry_id)
    return Result.new(proposals: {}, alternatives: {}) if bookings.empty?

    proposals = {}
    alternatives = {}
    used_entry_ids = Set.new
    propose_einzug(bookings, proposals, used_entry_ids)
    rest = bookings.reject { |b| proposals.key?(b.id) }
    propose_scored(rest, proposals, alternatives, used_entry_ids)
    Result.new(proposals: proposals, alternatives: alternatives)
  end

  # REVERSE direction: propose the best DATEV booking for each (unlinked)
  # accounting entry. Same channels, scoring and colours as `propose`, only the
  # roles are swapped. proposals = {entry_id => Match(booking:)}; alternatives =
  # {entry_id => [Match(booking:), ...]}. Used by the reconciliation entries
  # table (mirror of the bookings table's proposal column + candidate list).
  def self.propose_for_entries(entries)
    entries = entries.to_a
    # Drop already-linked entries with ONE query (entry.datev_booking per row
    # would be a 1000s-strong N+1 on a freshly-unlinked dataset).
    linked = DatevBooking.where(accounting_entry_id: entries.map(&:id))
      .where.not(accounting_entry_id: nil).pluck(:accounting_entry_id).to_set
    entries = entries.reject { |e| linked.include?(e.id) }
    return Result.new(proposals: {}, alternatives: {}) if entries.empty?

    proposals = {}
    alternatives = {}
    used_booking_ids = Set.new
    propose_einzug_for_entries(entries, proposals, used_booking_ids)
    rest = entries.reject { |e| proposals.key?(e.id) }
    propose_scored_for_entries(rest, proposals, alternatives, used_booking_ids)
    Result.new(proposals: proposals, alternatives: alternatives)
  end

  # Rate an EXISTING, explicit booking<->entry link in isolation (score + tier +
  # basis), computed for THIS pair only -- no candidate search over other
  # entries. Returns a Match, or nil when the pair carries no signal at all.
  #
  # An explicit automatic accounting_entry_link_type FIXES the rating
  # deterministically (tier :automatic, 100 %, its canonical basis) without
  # re-deriving it from the current texts -- the importer AND the UI connect set
  # that type for the two import-equivalent cases (see write_pairs /
  # detect_link_type). Otherwise the two matcher channels apply: the
  # Ende-zu-Ende-ID (Einzug) channel (=> :automatic) and the scored person/date
  # channel (=> a heuristic tier).
  #
  # ignore_person_link: when true, the scored channel does NOT short-circuit to
  # 100 % just because the booking's person is already the entry's person
  # ("Person bereits an der Buchung hinterlegt"); it rates the ACTUAL textual
  # name/date evidence instead. The booking detail page passes true so the chip
  # reflects the real match quality of an already-linked pair.
  def self.rate_pair(booking, entry, ignore_person_link: false)
    return nil unless booking && entry

    case booking.accounting_entry_link_type
    when "2025_fee_booking"
      return automatic_pair_match(booking, entry, "Beitrag aus 2025 (Personen-Nr + Valuta)")
    when "document_field_1_pre_notification"
      return automatic_pair_match(booking, entry, "Ende-zu-Ende-ID in Belegfeld 1")
    end

    rate_einzug_pair(booking, entry) ||
      rate_scored_pair(booking, entry, ignore_person_link: ignore_person_link)
  end

  # Connect the given proposals (or a subset via only_ids) in one UPDATE.
  # linked_by_id: the Person recorded as having made the links (the UI passes
  # current_user.id). Returns the number of connected pairs.
  def self.connect!(proposals, only_ids: nil, linked_by_id: nil)
    pairs = proposals
    pairs = pairs.slice(*Array(only_ids).map(&:to_i)) if only_ids
    return 0 if pairs.empty?

    write_pairs(pairs.map { |booking_id, match| [booking_id, match.entry] }, linked_by_id: linked_by_id)
  end

  # Manually connect ONE booking to ONE entry (from the alternatives list in
  # the detail view). Returns true when the link was written.
  # The booking's signed amount in cents as seen from the fee-account
  # (41030) side: `amount` is signed from the Konto perspective,
  # `offsetting_amount` from the Gegenkonto perspective. Empirically this
  # equals the linked entry's amount_cents (sign included) on every
  # historical pair -- the entry amount must match it exactly. Public: the
  # bookings controller uses it for the manual entry autocomplete.
  def self.signed_cents(booking)
    amount = if booking.account_number == FEE_ACCOUNT
      booking.amount
    else
      booking.offsetting_amount || -booking.amount
    end
    (amount * 100).round
  end

  def self.connect_pair!(booking, entry, linked_by_id: nil)
    return false if booking.accounting_entry_id || entry.datev_booking

    write_pairs([[booking.id, entry]], linked_by_id: linked_by_id) == 1
  end

  # Connect reverse proposals ({entry_id => Match(booking:)}) or a subset via
  # only_ids (entry ids). linked_by_id: see connect!. Returns the number of
  # connected pairs.
  def self.connect_reverse!(proposals, only_ids: nil, linked_by_id: nil)
    pairs = proposals
    pairs = pairs.slice(*Array(only_ids).map(&:to_i)) if only_ids
    return 0 if pairs.empty?

    write_pairs(pairs.map { |_entry_id, match| [match.booking.id, match.entry] }, linked_by_id: linked_by_id)
  end

  class << self
    private

    # --- single-pair rating (rate_pair), only for the given booking<->entry ---

    # A deterministic (:import => tier :automatic) Match for a link whose
    # accounting_entry_link_type already marks it import-equivalent: score 100,
    # the given canonical basis, no re-derivation from the current texts.
    def automatic_pair_match(booking, entry, basis)
      display = person_names_for([entry.subject_id].compact).dig(entry.subject_id, :display)
      Match.new(entry: entry, booking: booking, score: 100, kind: :import,
        basis: basis, person_name: display,
        details: "Beitragsbuchung ##{entry.id}\n#{basis}\n" \
          "Automatisch verknüpft (entspricht dem DATEV-Import-Kriterium)\nScore: 100 %")
    end

    # The automatic accounting_entry_link_type a link should carry, mirroring the
    # importer's two rules: "document_field_1_pre_notification" when the pair
    # satisfies the Ende-zu-Ende-ID (Einzug Belegfeld 1) channel,
    # "2025_fee_booking" when it satisfies the importer's 2025 fee rule (person id
    # with role prefix in the text + Valuta exactly on the booking date), else nil
    # (a genuine heuristic/manual link, whose quality the rating derives on the
    # fly). Used by write_pairs so a UI connect of one of those two cases is
    # stamped exactly like the importer would.
    def detect_link_type(booking, entry)
      return nil unless booking && entry
      return "document_field_1_pre_notification" if rate_einzug_pair(booking, entry)
      return "2025_fee_booking" if import_equivalent_2025?(booking, entry, booking_context(booking))
      nil
    end

    # Ende-zu-Ende-ID (Einzug Belegfeld 1) channel for ONE pair: the booking's
    # Einzug id resolves to the entry's pre-notification, the person id with its
    # role prefix stands in the Buchungstext, and the signed amount matches.
    def rate_einzug_pair(booking, entry)
      pn = booking.document_field_1.to_s[EINZUG_DF1, 1]&.to_i
      return nil unless pn && entry.direct_debit_pre_notification_id == pn

      person_number = booking.original_posting_text.to_s[PREFIXED_PERSON_ID, 1]
      return nil unless person_number && entry.subject_type == "Person" &&
        entry.subject_id == person_number.to_i
      return nil unless signed_cents(booking) == entry.amount_cents

      Match.new(entry: entry, booking: booking, score: 100, kind: :import,
        basis: "Ende-zu-Ende-ID in Belegfeld 1",
        person_name: person_names_for([entry.subject_id]).dig(entry.subject_id, :display),
        details: "Beitragsbuchung ##{entry.id}\nEnde-zu-Ende-ID in Belegfeld 1\n" \
          "Würde bereits vom DATEV-Import automatisch verknüpft\nScore: 100 %")
    end

    # Scored person/date channel for ONE pair.
    def rate_scored_pair(booking, entry, ignore_person_link: false)
      names = person_names_for([entry.subject_id].compact)
      context = booking_context(booking)
      entry_codes = {entry.id => extract_codes(entry.description)}
      scored = score_pair(booking, entry, names, context, entry_codes,
        ignore_person_link: ignore_person_link)
      scored && build_match(booking, scored)
    end

    # Write the given [booking_id, entry] links in one UPDATE and stamp the link
    # provenance (see doc/recon_linking.md): accounting_entry_link_type (the
    # import-equivalent type detected per pair via detect_link_type, else NULL for
    # a heuristic/manual link), accounting_entry_linked_at (now) and
    # accounting_entry_link_person_id (linked_by_id -- the acting user on a UI
    # connect). Only rows that pass the guard (target still unlinked) are touched,
    # so the provenance is stamped exactly on the pairs actually connected.
    def write_pairs(pairs, linked_by_id: nil)
      connection = DatevBooking.connection
      now = Time.zone.now
      # detect_link_type needs the booking object; callers pass only its id.
      bookings = DatevBooking.where(id: pairs.map(&:first)).index_by(&:id)
      rows = pairs.map { |booking_id, entry|
        person_id = (entry.subject_type == "Person") ? entry.subject_id : nil
        link_type = detect_link_type(bookings[booking_id], entry)
        tuple = [booking_id, entry.id, person_id, entry.camt_transaction_id, link_type]
        "(#{tuple.map { |v| connection.quote(v) }.join(", ")})"
      }.join(", ")
      connection.execute(<<~SQL).cmd_tuples
        UPDATE datev_bookings AS db SET
          accounting_entry_id = v.entry_id::bigint,
          person_id = v.person_id::bigint,
          camt_transaction_id = v.camt_id::bigint,
          accounting_entry_link_type = v.link_type::text,
          accounting_entry_link_person_id = #{connection.quote(linked_by_id)},
          accounting_entry_linked_at = #{connection.quote(now)},
          updated_at = #{connection.quote(now)}
        FROM (VALUES #{rows}) AS v(id, entry_id, person_id, camt_id, link_type)
        WHERE db.id = v.id::bigint
          AND db.accounting_entry_id IS NULL
          AND NOT EXISTS (SELECT 1 FROM datev_bookings other
                          WHERE other.accounting_entry_id = v.entry_id::bigint)
      SQL
    end

    # Candidate entries: not linked to any booking and not flagged as
    # excluded_from_fee_reconciliation ("von der Beitrags-Abstimmung
    # ausgenommen") -- flagged entries must never be proposed.
    def unlinked_entries
      AccountingEntry.where.missing(:datev_booking).fee_reconciliation_relevant
    end

    def person_names_for(person_ids)
      Person.where(id: person_ids)
        .pluck(:id, :first_name, :last_name, :sepa_name,
          :additional_contact_name_a, :additional_contact_name_b)
        .to_h { |id, first, last, sepa, contact_a, contact_b|
          variants = [[sepa, "SEPA-Name"], [contact_a, "Kontaktname"], [contact_b, "Kontaktname"]]
            .filter_map { |value, label| name_variant(value, label) }
          first_norm = normalize(first.to_s[/\S+/])
          last_norm = normalize(last)
          own = (first_norm.present? && last_norm.present?) ? [first_norm[0], last_norm[0]] : nil
          [id, {first_norm: first_norm, last_norm: last_norm,
                display: "#{first} #{last}".strip, variants: variants,
                own_initials: own,
                holder_initials: holder_initial_pairs(sepa, contact_a, contact_b)}]
        }
    end

    # Initial pairs [first, last] of the person's SEPA account holders /
    # additional contacts, for matching anonymised booking texts such as
    # "Konto A.M. und B.M." (fictional Anna Mustermann, Bernd Mustermann).
    # Combined holder names ("Anna & Bernd Mustermann") are split so both
    # holders are captured.
    def holder_initial_pairs(*raw_names)
      raw_names.compact
        .flat_map { |name| name.split(/&|\+|,|\/|\bund\b/i) }
        .filter_map { |sub|
          words = normalize(sub).scan(/[a-z]+/)
          [words.first[0], words.last[0]] if words.size >= 2
        }.uniq
    end

    # An alternative full name of the person (SEPA account holder, additional
    # contact) that may appear in the Buchungstext instead of the person's own
    # name (e.g. a parent paying the fee, with a different surname). Only
    # multi-word names count -- a single word is too weak a signal. For the
    # fuzzy check the name is reduced to its alphabetic tokens (>= 3 chars):
    # punctuation fragments like the "e.v." of an organisation name would
    # otherwise never match the text's word list.
    def name_variant(value, label)
      full = normalize(value)
      words = full.scan(/[a-z]{3,}/)
      {full: full, words: words, label: label} if words.size >= 2 && full.length >= 6
    end

    # Channel 1: Einzug Belegfeld -> pre-notification id -> unique entry of
    # the person named in the text. Cell shows entry + person name, but no
    # person id and no score breakdown.
    def propose_einzug(bookings, proposals, used_entry_ids)
      by_pn = {}
      bookings.each do |b|
        pn = b.document_field_1.to_s[EINZUG_DF1, 1]
        by_pn[b] = pn.to_i if pn
      end
      return if by_pn.empty?

      entries = unlinked_entries
        .where(direct_debit_pre_notification_id: by_pn.values.uniq)
        .group_by(&:direct_debit_pre_notification_id)
      names = person_names_for(entries.values.flatten.map(&:subject_id).uniq)
      by_pn.each do |booking, pn|
        candidates = entries[pn]
        next unless candidates&.size == 1
        entry = candidates.first
        next if used_entry_ids.include?(entry.id)
        person_number = booking.original_posting_text.to_s[PREFIXED_PERSON_ID, 1]
        next unless person_number && entry.subject_type == "Person" &&
          entry.subject_id == person_number.to_i
        next unless signed_cents(booking) == entry.amount_cents
        used_entry_ids << entry.id
        proposals[booking.id] = Match.new(entry: entry, score: 100, kind: :import,
          basis: "Ende-zu-Ende-ID in Belegfeld 1",
          person_name: names.dig(entry.subject_id, :display),
          details: "Beitragsbuchung ##{entry.id}\nEnde-zu-Ende-ID in Belegfeld 1\n" \
            "Würde bereits vom DATEV-Import automatisch verknüpft\nScore: 100 %")
      end
    end

    # Channel 2: scored person/date matching over one batched candidate load.
    def propose_scored(bookings, proposals, alternatives, used_entry_ids)
      return if bookings.empty?

      cents_set = bookings.map { |b| signed_cents(b) }.uniq
      dates = bookings.filter_map(&:booking_date)
      return if dates.empty?

      contexts = bookings.to_h { |b| [b.id, booking_context(b)] }
      pool_entries = unlinked_entries
        .where(subject_type: "Person")
        .where(amount_cents: cents_set)
        .where("accounting_entries.value_date BETWEEN :from AND :to " \
               "OR accounting_entries.booking_date BETWEEN :from AND :to",
          from: dates.min - WIDE_DATE_WINDOW, to: dates.max + WIDE_DATE_WINDOW)
        .to_a
      # Reference codes make a pair date-independent, so entries carrying any
      # of the bookings' codes join the pool regardless of their dates.
      all_codes = contexts.values.flat_map { |c| c[:codes].to_a }.uniq
      if all_codes.any?
        pattern = all_codes.map { |c| Regexp.escape(c) }.join("|")
        code_entries = unlinked_entries
          .where(subject_type: "Person")
          .where(amount_cents: cents_set)
          .where("accounting_entries.description ~* ?", "(#{pattern})")
          .to_a
        pool_entries = (pool_entries + code_entries).uniq(&:id)
      end
      entry_codes = pool_entries.to_h { |e| [e.id, extract_codes(e.description)] }
      # Names via pluck -- instantiating thousands of full Person records just
      # for the name columns would dominate the runtime.
      names = person_names_for(pool_entries.map(&:subject_id).uniq)
      candidates = pool_entries.group_by(&:amount_cents)
      # Person-id / last-name indexes, used to NARROW very large same-amount
      # groups (see narrow_entry_pool) so scoring stays O(text signals), not
      # O(bookings × group size). Built once.
      entries_by_person = pool_entries.group_by(&:subject_id)
      entries_by_lastname = {}
      pool_entries.each do |e|
        ln = names.dig(e.subject_id, :last_norm)
        (entries_by_lastname[ln] ||= []) << e if ln.present?
      end

      bookings.each do |booking|
        next if booking.booking_date.nil?
        cents = signed_cents(booking)
        context = contexts[booking.id]
        pool = narrow_entry_pool(candidates[cents] || [], booking, context, entries_by_person, entries_by_lastname)
          .reject { |e| used_entry_ids.include?(e.id) }
        next if pool.empty?

        scored = pool.filter_map { |entry| score_pair(booking, entry, names, context, entry_codes) }
          .sort_by { |s| -s[:score] }
        next if scored.empty?

        best = scored.take_while { |s| s[:score] == scored.first[:score] }
        if best.size == 1
          match = build_match(booking, best.first)
          used_entry_ids << match.entry.id
          proposals[booking.id] = match
          next if match.score >= 100 # sure -> no alternatives needed
        end
        alternatives[booking.id] = scored.first(MAX_ALTERNATIVES)
          .map { |s| build_match(booking, s) }
      end
    end

    # The booking's text-derived matching context, computed once per booking.
    def booking_context(booking)
      raw_text = booking.original_posting_text.to_s
      text_norm = normalize(booking.description.presence || raw_text)
      {
        text_norm: text_norm,
        words: text_norm.scan(/[a-z]{4,}/).uniq,
        prefixed_id: raw_text[PREFIXED_PERSON_ID, 1]&.to_i,
        numbers: raw_text.scan(/\d+/).to_set,
        # Initial pairs "X.Y." in the (anonymised) text, e.g.
        # "YP C.M. / Konto A.M. und B.M." -> {[c,m],[a,m],[b,m]}. Only adjacent
        # initials with dots count -- "YP" (no dots) is not captured.
        initials: extract_initial_pairs(text_norm),
        # Codes live in the texts AND in the Belegfelder (e.g. Belegfeld 1
        # "HELP-1234" on Abmeldungs-Rückzahlungen).
        codes: extract_codes([booking.description, raw_text,
          booking.document_field_1, booking.document_field_2].join(" "))
      }
    end

    def extract_codes(text)
      text.to_s.scan(REFERENCE_CODE).map(&:upcase).to_set
    end

    # Adjacent-initials pairs "X.Y." in a normalised text (lower-cased, no
    # diacritics), e.g. "c.m." -> [["c","m"]]. Whitespace between the two
    # letters is allowed ("c. m."); a separator (slash, word) is not, so
    # "a.m. und b.m." yields two pairs, never a cross "m./b".
    INITIAL_PAIR = /(?<![a-z])([a-z])\.\s*([a-z])\./
    def extract_initial_pairs(text_norm)
      text_norm.to_s.scan(INITIAL_PAIR).map { |a, b| [a, b] }.to_set
    end

    # A 2025 pair the DATEV IMPORT itself would link, so it counts as an
    # import-exact (green) match rather than a heuristic one: the person id with
    # its role prefix stands in the Buchungstext AND the entry's Valuta is
    # exactly the booking date. This mirrors the importer's 2025 rule
    # (wsjrdp_scripts `_match_2025_fee_entries`: person id from the text, the
    # exact signed amount, value_date = booking_date); the amount is already
    # guaranteed by the candidate pool, and only unambiguous best hits are
    # proposed at all.
    def import_equivalent_2025?(booking, entry, context)
      booking.booking_date&.year == 2025 &&
        context[:prefixed_id].present? &&
        context[:prefixed_id] == entry.subject_id &&
        entry.value_date == booking.booking_date
    end

    def score_pair(booking, entry, names, context, entry_codes, ignore_person_link: false)
      name = names[entry.subject_id]
      return nil unless name

      person_score, person_reason = person_component(booking, entry, name, context,
        ignore_person_link: ignore_person_link)
      return nil unless person_score

      date_score, date_reason = date_component(booking, entry)
      # A shared reference code (e.g. "HELP-1234" in both texts) identifies
      # the pair regardless of the date distance -- it overrides the date
      # component entirely (refunds are often booked weeks later).
      shared_codes = context[:codes] & (entry_codes[entry.id] || Set.new)
      if shared_codes.any?
        date_score = 100
        date_reason = "Referenz #{shared_codes.min} in beiden Texten"
      end
      return nil unless date_score

      {entry: entry, name: name, score: (person_score * date_score / 100.0).round,
       person_score: person_score, person_reason: person_reason,
       date_score: date_score, date_reason: date_reason,
       import: import_equivalent_2025?(booking, entry, context)}
    end

    def person_component(booking, entry, name, context, ignore_person_link: false)
      # A booking whose person is already set trivially "matches" that person --
      # useless for judging an EXISTING link's textual quality, so the booking
      # detail rating turns this shortcut off (ignore_person_link) and falls
      # through to the real name/id evidence below.
      if booking.person_id && !ignore_person_link
        return (booking.person_id == entry.subject_id) ?
          [100, "Person bereits an der Buchung hinterlegt"] : nil
      end

      text = context[:text_norm]
      return nil if text.blank?

      if context[:prefixed_id] == entry.subject_id
        return [100, "Personen-Nr mit Präfix im Buchungstext"]
      end

      first = name[:first_norm]
      last = name[:last_norm]
      first_exact = first.present? && text.include?(first)
      last_exact = last.present? && text.include?(last)
      return [100, "Voller Name im Buchungstext"] if first_exact && last_exact

      first_fuzzy = first_exact || fuzzy_word?(context[:words], first)
      last_fuzzy = last_exact || fuzzy_word?(context[:words], last)
      return [85, "Name ähnlich im Buchungstext"] if first_fuzzy && last_fuzzy

      # Alternative full names (SEPA account holder, additional contacts) --
      # e.g. a parent with a different surname paying the fee.
      variants = name[:variants] || []
      if (v = variants.find { |var| text.include?(var[:full]) })
        return [80, "#{v[:label]} im Buchungstext"]
      end
      return [70, "Nachname im Buchungstext"] if last_exact
      if (v = variants.find { |var| variant_fuzzy?(var, text, context) })
        return [65, "#{v[:label]} ähnlich im Buchungstext"]
      end
      return [60, "Nachname ähnlich im Buchungstext"] if last_fuzzy
      if context[:numbers].include?(entry.subject_id.to_s)
        return [60, "Personen-Nr ohne Präfix im Buchungstext"]
      end
      return [40, "Nur Vorname im Buchungstext"] if first_exact
      return [30, "Nur Vorname ähnlich im Buchungstext"] if first_fuzzy
      initials_component(name, context)
    end

    # Lowest-confidence fallback for fully anonymised booking texts that carry
    # only initials, e.g. Abmeldungs-Rückzahlungen exported as
    # "YP P.D. / Konto S.D. und G.D.". The person's own initials must be among
    # the text's initial pairs; matching SEPA account-holder initials on top
    # (the "Konto ..." holders) raise the confidence. Never :sure -- initials
    # are weak, so this only ever surfaces as a heuristic proposal/alternative,
    # and the exact-amount rule (an entry is a candidate only at the identical
    # signed cents) keeps the pool tiny.
    def initials_component(name, context)
      pairs = context[:initials]
      own = name[:own_initials]
      return nil if pairs.blank? || own.nil? || !pairs.include?(own)

      holders = (name[:holder_initials] || []).select { |h| h != own && pairs.include?(h) }
      case holders.size
      when 0 then [45, "Initialen der Person im Buchungstext"]
      when 1 then [65, "Initialen Person + Kontoinhaber im Buchungstext"]
      else [75, "Initialen Person + Kontoinhaber im Buchungstext"]
      end
    end

    # Both entry dates count (Valuta AND the entry's own Buchungsdatum can
    # legitimately differ); the better one wins. Beyond WIDE_DATE_WINDOW
    # (~three months) a pair is NEVER a candidate (only a shared reference
    # code overrides that, in score_pair).
    def date_component(booking, entry)
      best = nil
      {"Valuta" => entry.value_date, "Buchungsdatum" => entry.booking_date}.each do |label, date|
        next unless date
        diff = (date - booking.booking_date).abs.to_i
        score = if diff.zero?
          100
        elsif diff <= DATE_WINDOW
          70
        elsif diff <= WIDE_DATE_WINDOW
          40
        end
        next unless score
        reason = diff.zero? ? "#{label} exakt" : "#{label} ±#{diff} Tag(e)"
        best = [score, reason] if best.nil? || score > best[0]
      end
      best
    end

    # Small-typo tolerance: any sufficiently similar word in the text
    # (Levenshtein distance 1, or 2 for longer names). Cheap prefilters keep
    # the hot loop fast.
    # Every word of the alternative name must appear in the text -- long words
    # with typo tolerance (fuzzy_word?), short ones (< 4 chars, e.g. "de",
    # "von") as exact substrings.
    def variant_fuzzy?(variant, text, context)
      variant[:words].all? { |word|
        (word.length < 4) ? text.include?(word) : fuzzy_word?(context[:words], word)
      }
    end

    def fuzzy_word?(words, target)
      return false if target.blank? || target.length < 4
      max_dist = (target.length >= 7) ? 2 : 1
      words.any? { |word|
        (word.length - target.length).abs <= max_dist &&
          (word[0] == target[0] || word[1] == target[1]) &&
          DidYouMean::Levenshtein.distance(word, target) <= max_dist
      }
    end

    def build_match(booking, scored)
      entry = scored[:entry]
      entry_dates = ["Valuta #{entry.value_date ? I18n.l(entry.value_date) : "—"}",
        "Buchungsdatum #{entry.booking_date ? I18n.l(entry.booking_date) : "—"}"].join(" · ")
      details = [
        "Beitragsbuchung ##{entry.id}",
        "Person: #{scored[:name][:display]}",
        "Buchung #{I18n.l(booking.booking_date)} · Entry: #{entry_dates}",
        "Person-Match: #{scored[:person_reason]} (#{scored[:person_score]} %)",
        "Datums-Match: #{scored[:date_reason]} (#{scored[:date_score]} %)",
        "Score: #{scored[:person_score]} % × #{scored[:date_score]} % = #{scored[:score]} %"
      ]
      details << "Würde bereits vom DATEV-Import automatisch verknüpft (2025-Regel)" if scored[:import]
      Match.new(entry: entry, score: scored[:score],
        kind: scored[:import] ? :import : :heuristic,
        basis: scored[:import] ?
          "Personen-Nr + Valuta exakt (2025-Import-Regel)" :
          "#{scored[:person_reason]}, #{scored[:date_reason]}",
        person_name: scored[:name][:display], details: details.join("\n"))
    end

    def normalize(string)
      string.to_s.unicode_normalize(:nfkd).gsub(/\p{Mn}/, "").downcase
    end

    # Narrow a same-amount ENTRY group (forward direction) when it is very large:
    # keep only entries whose person is strongly signalled in the booking text
    # (person_id already set, prefixed id, a plain number = the id, or an exact
    # last-name token). Small groups are scored in full (keeps fuzzy + initials).
    def narrow_entry_pool(group, booking, context, by_person, by_lastname)
      return group if group.size <= BIG_AMOUNT_GROUP
      gids = group.map(&:id).to_set
      cand = []
      cand.concat(by_person[booking.person_id] || []) if booking.person_id
      cand.concat(by_person[context[:prefixed_id]] || []) if context[:prefixed_id]
      context[:numbers].each { |num| cand.concat(by_person[num.to_i] || []) }
      context[:words].each { |word| cand.concat(by_lastname[word] || []) }
      cand.uniq(&:id).select { |e| gids.include?(e.id) }
    end

    # Narrow a same-amount BOOKING group (reverse direction) the same way: keep
    # bookings whose text names the entry's person (id in the numbers, or the
    # exact last name among the words).
    def narrow_booking_pool(group, entry, name, by_number, by_word)
      return group if group.size <= BIG_AMOUNT_GROUP
      gids = group.map(&:id).to_set
      cand = []
      cand.concat(by_number[entry.subject_id.to_s] || [])
      cand.concat(by_word[name[:last_norm]] || []) if name[:last_norm].present?
      cand.uniq(&:id).select { |b| gids.include?(b.id) }
    end

    # --- reverse direction (entry -> booking) --------------------------------

    # Reverse channel 1: an entry with a pre-notification id -> the unlinked
    # Einzug booking whose Belegfeld 1 resolves to that id (import-deterministic).
    def propose_einzug_for_entries(entries, proposals, used_booking_ids)
      by_pn = entries.select(&:direct_debit_pre_notification_id).group_by(&:direct_debit_pre_notification_id)
      return if by_pn.empty?

      bookings = DatevBooking.where(accounting_entry_id: nil)
        .where("document_field_1 LIKE 'Einzug-%'").to_a
      names = person_names_for(entries.map(&:subject_id).uniq)
      bookings.each do |booking|
        pn = booking.document_field_1.to_s[EINZUG_DF1, 1]&.to_i
        next unless pn
        candidates = by_pn[pn]
        next unless candidates&.size == 1
        entry = candidates.first
        next if proposals.key?(entry.id) || used_booking_ids.include?(booking.id)
        person_number = booking.original_posting_text.to_s[PREFIXED_PERSON_ID, 1]
        next unless person_number && entry.subject_type == "Person" &&
          entry.subject_id == person_number.to_i
        next unless signed_cents(booking) == entry.amount_cents
        used_booking_ids << booking.id
        proposals[entry.id] = Match.new(booking: booking, entry: entry, score: 100, kind: :import,
          basis: "Ende-zu-Ende-ID in Belegfeld 1",
          person_name: names.dig(entry.subject_id, :display),
          details: "DATEV-Buchung ##{booking.id}\nEnde-zu-Ende-ID in Belegfeld 1\n" \
            "Würde bereits vom DATEV-Import automatisch verknüpft\nScore: 100 %")
      end
    end

    # Reverse channel 2: scored person/date/initials matching over one batched
    # candidate-booking load (unlinked, fee-account side, matching amount, within
    # the date window or sharing a reference code).
    def propose_scored_for_entries(entries, proposals, alternatives, used_booking_ids)
      entries = entries.select { |e| e.subject_type == "Person" }
      return if entries.empty?

      amounts = entries.map(&:amount_cents).uniq
      dates = entries.filter_map { |e| e.value_date || e.booking_date }
      return if dates.empty?

      fee = "(account_number = '#{FEE_ACCOUNT}' OR offsetting_account_number = '#{FEE_ACCOUNT}')"
      pool = DatevBooking.where(accounting_entry_id: nil).where(Arel.sql(fee))
        .where("booking_date BETWEEN :from AND :to",
          from: dates.min - WIDE_DATE_WINDOW, to: dates.max + WIDE_DATE_WINDOW).to_a
      entry_codes = entries.to_h { |e| [e.id, extract_codes(e.description)] }
      all_codes = entry_codes.values.flat_map(&:to_a).uniq
      if all_codes.any?
        pattern = all_codes.map { |c| Regexp.escape(c) }.join("|")
        code_pool = DatevBooking.where(accounting_entry_id: nil).where(Arel.sql(fee))
          .where("document_field_1 ~* :p OR document_field_2 ~* :p OR description ~* :p OR original_posting_text ~* :p",
            p: "(#{pattern})").to_a
        pool = (pool + code_pool).uniq(&:id)
      end
      candidates = pool.select { |b| amounts.include?(signed_cents(b)) }
      return if candidates.empty?

      contexts = candidates.to_h { |b| [b.id, booking_context(b)] }
      names = person_names_for(entries.map(&:subject_id).uniq)
      by_amount = candidates.group_by { |b| signed_cents(b) }
      # Number / last-name-word indexes over the candidate bookings' texts, to
      # narrow very large same-amount groups (see narrow_booking_pool).
      bk_by_number = {}
      bk_by_word = {}
      candidates.each do |b|
        ctx = contexts[b.id]
        ctx[:numbers].each { |n| (bk_by_number[n] ||= []) << b }
        ctx[:words].each { |w| (bk_by_word[w] ||= []) << b }
      end

      entries.each do |entry|
        name = names[entry.subject_id]
        next unless name
        pool_for_entry = narrow_booking_pool(by_amount[entry.amount_cents] || [], entry, name, bk_by_number, bk_by_word)
          .reject { |b| used_booking_ids.include?(b.id) }
        next if pool_for_entry.empty?

        scored = pool_for_entry.filter_map { |b|
          s = score_pair(b, entry, names, contexts[b.id], entry_codes)
          s&.merge(booking: b)
        }.sort_by { |s| -s[:score] }
        next if scored.empty?

        best = scored.take_while { |s| s[:score] == scored.first[:score] }
        if best.size == 1
          match = build_reverse_match(entry, best.first)
          used_booking_ids << match.booking.id
          proposals[entry.id] = match
          next if match.score >= 100
        end
        alternatives[entry.id] = scored.first(MAX_ALTERNATIVES).map { |s| build_reverse_match(entry, s) }
      end
    end

    def build_reverse_match(entry, scored)
      booking = scored[:booking]
      details = [
        "DATEV-Buchung ##{booking.id}",
        "Person: #{scored[:name][:display]}",
        "Buchung #{I18n.l(booking.booking_date)} · #{booking.description.to_s.truncate(60)}",
        "Person-Match: #{scored[:person_reason]} (#{scored[:person_score]} %)",
        "Datums-Match: #{scored[:date_reason]} (#{scored[:date_score]} %)",
        "Score: #{scored[:person_score]} % × #{scored[:date_score]} % = #{scored[:score]} %"
      ]
      details << "Würde bereits vom DATEV-Import automatisch verknüpft (2025-Regel)" if scored[:import]
      Match.new(booking: booking, entry: entry, score: scored[:score],
        kind: scored[:import] ? :import : :heuristic,
        basis: scored[:import] ?
          "Personen-Nr + Valuta exakt (2025-Import-Regel)" :
          "#{scored[:person_reason]}, #{scored[:date_reason]}",
        person_name: scored[:name][:display], details: details.join("\n"))
    end
  end
end
