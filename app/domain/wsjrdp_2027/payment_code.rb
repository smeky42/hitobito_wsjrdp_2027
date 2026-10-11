# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "securerandom"

module Wsjrdp2027
  # Payment codes as wsjrdp_scripts specifies them (docs/payment_code.md,
  # wsjrdp2027._payment_code): an ISO 11649 creditor reference "RFpp" around
  # a codeword of Crockford base32 symbols, data symbols followed by
  # Reed-Solomon parity symbols over GF(32).
  #
  #   RF75 K7M3 QX9P NFK3     printed
  #   RF75K7M3QX9PNFK3        electronic, 16 characters
  #
  # The Reed-Solomon code uses the primitive polynomial x^5 + x^2 + 1, the
  # generator 2 and the first consecutive root 1; the parity is systematic,
  # after the data. The test vectors of wsjrdp_scripts
  # (spec/fixtures/payment_code_vectors.json here) pin both implementations
  # to the same codes.
  #
  # This module makes and checks codes; matching a typed code to an issued
  # one is the bank statement import's business (wsjrdp_scripts).
  module PaymentCode
    ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

    DATA_LENGTH = 8
    PARITY_LENGTH = 4
    # The most symbols an ISO 11649 reference holds after RFpp.
    RF_MAX_CODEWORD_LENGTH = 21

    RS_FIELD_EXPONENT = 5
    RS_PRIMITIVE_POLYNOMIAL = 0x25
    RS_GENERATOR = 2
    RS_FCR = 1
    # The longest Reed-Solomon code over GF(32): data and parity together.
    RS_MAX_LENGTH = ALPHABET.length - 1

    # The distances a new code keeps to every issued one (see
    # generate_distinct_codeword).
    MIN_HAMMING_DISTANCE = 8
    MIN_LEVENSHTEIN_DISTANCE = 4
    MAX_GENERATION_ATTEMPTS = 10

    SEPARATORS = /[\s-]+/
    LOOKALIKES = ["OIL", "011"].freeze

    class Error < StandardError; end

    # The issued codewords, prepared for the distance questions a new draw
    # asks: the smallest Hamming and Levenshtein distance to any of them.
    # The answers are exact, the same as comparing with every codeword one by
    # one; the index only skips work that cannot change them:
    #
    # - Hamming compares two codewords packed into integers, 5 bits a symbol.
    # - Levenshtein is never smaller than the bag distance (how many symbols
    #   one codeword has that the other lacks), so a codeword whose bag
    #   distance is not below the smallest Levenshtein distance found so far
    #   is skipped, and the rest is computed only up to that distance.
    class Index
      Entry = Struct.new(:codeword, :packed, :counts)

      attr_reader :size

      def initialize(codewords = [])
        @entries = []
        @size = 0
        codewords.each { |codeword| add(codeword) }
      end

      def add(codeword)
        codeword = codeword.to_s.gsub(SEPARATORS, "").upcase
        @entries << Entry.new(codeword, PaymentCode.pack(codeword), PaymentCode.symbol_counts(codeword))
        @size += 1
        self
      end

      alias_method :<<, :add

      # [smallest Hamming distance, smallest Levenshtein distance] of codeword
      # to the issued codewords; one more than its length where there is none
      # to compare with. Hamming counts only codewords of the same length.
      def distances(codeword)
        packed = PaymentCode.pack(codeword)
        counts = PaymentCode.symbol_counts(codeword)
        hamming = levenshtein = codeword.length + 1
        @entries.each do |entry|
          if entry.codeword.length == codeword.length
            distance = if packed && entry.packed
              PaymentCode.packed_hamming_distance(packed, entry.packed, codeword.length)
            else
              PaymentCode.hamming_distance(codeword, entry.codeword)
            end
            hamming = distance if distance < hamming
          end
          next if PaymentCode.bag_distance(counts, entry.counts, codeword.length, entry.codeword.length) >= levenshtein

          distance = PaymentCode.levenshtein_distance(codeword, entry.codeword, bound: levenshtein)
          levenshtein = distance if distance < levenshtein
        end
        [hamming, levenshtein]
      end
    end

    # GF(32): exp[i] = 2^i for i in 0...62 (the table runs twice so that a
    # sum of two logarithms needs no reduction), log the inverse.
    FIELD_SIZE = 2**RS_FIELD_EXPONENT
    EXP, LOG = begin
      exp = Array.new(2 * (FIELD_SIZE - 1), 0)
      log = Array.new(FIELD_SIZE, 0)
      x = 1
      (FIELD_SIZE - 1).times do |i|
        exp[i] = x
        log[x] = i
        x <<= 1
        x ^= RS_PRIMITIVE_POLYNOMIAL if x.anybits?(FIELD_SIZE)
      end
      (FIELD_SIZE - 1).upto(exp.size - 1) { |i| exp[i] = exp[i - (FIELD_SIZE - 1)] }
      [exp.freeze, log.freeze]
    end

    module_function

    # The data symbols followed by parity_length Reed-Solomon parity symbols.
    def encode_codeword(data, parity_length: PARITY_LENGTH)
      data = data.to_s
      if data.empty? || data.length + parity_length > RS_MAX_LENGTH || data.each_char.any? { |c| !ALPHABET.include?(c) }
        raise ArgumentError, "expected 1 to #{RS_MAX_LENGTH - parity_length} symbols of #{ALPHABET}, got #{data.inspect}"
      end

      message = symbols(data)
      generator = generator_polynomial(parity_length)
      remainder = message + Array.new(parity_length, 0)
      message.each_index do |i|
        coefficient = remainder[i]
        next if coefficient.zero?

        1.upto(generator.size - 1) { |j| remainder[i + j] ^= gf_mul(generator[j], coefficient) }
      end
      data + codeword_from_symbols(remainder.last(parity_length))
    end

    # Whether codeword is a Reed-Solomon codeword of these lengths: all its
    # syndromes are zero.
    def valid_codeword?(codeword, data_length: DATA_LENGTH, parity_length: PARITY_LENGTH)
      codeword = codeword.to_s
      return false unless codeword.length == data_length + parity_length
      return false if codeword.each_char.any? { |c| !ALPHABET.include?(c) }

      values = symbols(codeword)
      parity_length.times.all? { |i| poly_eval(values, EXP[(RS_FCR + i) % (FIELD_SIZE - 1)]).zero? }
    end

    # The ISO 11649 check digits of a codeword (ISO 7064 MOD 97-10).
    def check_digits(codeword)
      format("%02d", (98 - (100 * (base10(codeword + "RF") % 97))) % 97)
    end

    # The electronic form RFpp + codeword.
    def code_from_codeword(codeword) = "RF#{check_digits(codeword)}#{codeword}"

    # Upper case, without spaces and hyphens, look-alikes mapped in the
    # codeword and the check digits (O to 0, I and L to 1).
    def compact(code)
      compact = code.to_s.gsub(SEPARATORS, "").upcase
      return "RF#{compact[2..].tr(*LOOKALIKES)}" if compact.start_with?("RF")

      compact.tr(*LOOKALIKES)
    end

    # The printed form: groups of four.
    def format_code(code) = compact(code).scan(/.{1,4}/).join(" ")

    # The codeword of a code.
    def codeword_of(code) = compact(code)[4..].to_s

    # Whether code has valid RF check digits and a valid codeword of these
    # lengths.
    def valid?(code, data_length: DATA_LENGTH, parity_length: PARITY_LENGTH)
      compact = compact(code)
      compact.length == 4 + data_length + parity_length &&
        compact.start_with?("RF") && compact[2, 2].match?(/\A\d{2}\z/) &&
        (base10(compact[4..] + compact[0, 4]) % 97) == 1 &&
        valid_codeword?(compact[4..], data_length: data_length, parity_length: parity_length)
    end

    # data_length random symbols followed by parity_length parity symbols.
    def generate_codeword(data_length: DATA_LENGTH, parity_length: PARITY_LENGTH, random_data: nil)
      data = random_data ? random_data.call : Array.new(data_length) { ALPHABET[SecureRandom.random_number(ALPHABET.length)] }.join
      raise ArgumentError, "expected #{data_length} data symbols, got #{data.inspect}" unless data.length == data_length

      encode_codeword(data, parity_length: parity_length)
    end

    # A new codeword far enough from every issued one: at least
    # min_hamming_distance and min_levenshtein_distance to each of them.
    # After max_attempts draws without one it returns the draw farthest from
    # the issued codewords (largest Hamming distance first, then largest
    # Levenshtein distance), or raises with raise_when_too_close. A codeword
    # equal to an issued one is never returned.
    def generate_distinct_codeword(issued_codewords = [], data_length: DATA_LENGTH, parity_length: PARITY_LENGTH,
      min_hamming_distance: MIN_HAMMING_DISTANCE, min_levenshtein_distance: MIN_LEVENSHTEIN_DISTANCE,
      max_attempts: MAX_GENERATION_ATTEMPTS, raise_when_too_close: false, random_data: nil)
      raise ArgumentError, "max_attempts must be at least 1, got #{max_attempts}" if max_attempts < 1

      issued = issued_codewords.is_a?(Index) ? issued_codewords : Index.new(issued_codewords)
      best_codeword = nil
      best_distances = [-1, -1]
      max_attempts.times do
        codeword = generate_codeword(data_length: data_length, parity_length: parity_length, random_data: random_data)
        distances = issued.distances(codeword)
        return codeword if distances[0] >= min_hamming_distance && distances[1] >= min_levenshtein_distance

        best_codeword, best_distances = codeword, distances if (distances <=> best_distances) == 1
      end
      if raise_when_too_close || best_distances[1].zero?
        raise Error, "no code far enough from #{issued.size} issued codes in #{max_attempts} attempts"
      end

      best_codeword
    end

    # A new payment code whose codeword is far enough from the codewords of
    # every issued code (see generate_distinct_codeword).
    def generate_distinct(issued_codes = [], data_length: DATA_LENGTH, parity_length: PARITY_LENGTH, **options)
      if data_length + parity_length > RF_MAX_CODEWORD_LENGTH
        raise ArgumentError, "an RF reference holds at most #{RF_MAX_CODEWORD_LENGTH} symbols, " \
          "got #{data_length} + #{parity_length}"
      end

      codeword = generate_distinct_codeword(issued_codes.map { |code| codeword_of(code) },
        data_length: data_length, parity_length: parity_length, **options)
      code_from_codeword(codeword)
    end

    # The smallest Hamming and Levenshtein distances of codeword to the issued
    # codewords (an Index or a list); one more than its length where there is
    # none to compare with. Hamming counts only codewords of the same length.
    def distances(codeword, issued)
      (issued.is_a?(Index) ? issued : Index.new(issued)).distances(codeword)
    end

    def hamming_distance(a, b) = a.each_char.zip(b.each_char).count { |x, y| x != y }

    # The symbols of codeword, 5 bits each, as one integer; nil for a
    # codeword with a symbol outside the alphabet.
    def pack(codeword)
      codeword.each_char.reduce(0) do |packed, char|
        value = ALPHABET.index(char)
        return nil unless value

        (packed << 5) | value
      end
    end

    # The low bit of each 5-bit group, for codewords of up to RS_MAX_LENGTH
    # symbols.
    GROUP_LOW_BITS = (0...RS_MAX_LENGTH).sum { |i| 1 << (5 * i) }

    # How many symbols two packed codewords of length symbols differ in.
    def packed_hamming_distance(a, b, length)
      x = a ^ b
      differing = (x | (x >> 1) | (x >> 2) | (x >> 3) | (x >> 4)) & GROUP_LOW_BITS & ((1 << (5 * length)) - 1)
      differing.to_s(2).count("1")
    end

    # How often each character occurs in codeword.
    def symbol_counts(codeword) = codeword.each_char.tally

    # The bag distance of two codewords: the larger of how many characters
    # the one has that the other lacks, either way. Never larger than their
    # Levenshtein distance.
    def bag_distance(counts_a, counts_b, length_a, length_b)
      common = counts_a.sum { |char, count| [count, counts_b.fetch(char, 0)].min }
      [length_a, length_b].max - common
    end

    # The Levenshtein distance of a and b; with bound, any distance not below
    # bound comes back as bound, which is all a smallest distance needs.
    def levenshtein_distance(a, b, bound: nil)
      previous = (0..b.length).to_a
      a.each_char.with_index(1) do |char_a, i|
        current = [i]
        b.each_char.with_index(1) do |char_b, j|
          current << [previous[j] + 1, current[j - 1] + 1, previous[j - 1] + ((char_a == char_b) ? 0 : 1)].min
        end
        return bound if bound && current.min >= bound

        previous = current
      end
      bound ? [previous.last, bound].min : previous.last
    end

    def symbols(codeword) = codeword.each_char.map { |char| ALPHABET.index(char) }

    def codeword_from_symbols(values) = values.map { |value| ALPHABET[value] }.join

    def gf_mul(a, b)
      return 0 if a.zero? || b.zero?

      EXP[LOG[a] + LOG[b]]
    end

    # (x - a^(fcr)) (x - a^(fcr+1)) ... with the highest coefficient first.
    def generator_polynomial(parity_length)
      parity_length.times.reduce([1]) do |polynomial, i|
        root = EXP[(RS_FCR + i) % (FIELD_SIZE - 1)]
        product = Array.new(polynomial.size + 1, 0)
        polynomial.each_with_index do |coefficient, j|
          product[j] ^= coefficient
          product[j + 1] ^= gf_mul(coefficient, root)
        end
        product
      end
    end

    # Horner, highest coefficient first.
    def poly_eval(polynomial, x)
      polynomial.reduce(0) { |y, coefficient| gf_mul(y, x) ^ coefficient }
    end

    # Letters as 10..35, digits as they are -- the number ISO 7064 works on.
    def base10(string) = string.each_char.map { |char| char.to_i(36).to_s }.join.to_i
  end
end
