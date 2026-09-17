# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Only the unidecoder. `require "stringex"` would also load acts_as_url, which
# extends ActiveRecord::Base with a public `included` -- and every model that
# declares `scope :included` (the core's Subscription, SubscriptionTag,
# CalendarTag, CalendarGroup) then refuses to load, which breaks each code
# reload in development.
require "stringex/unidecoder"

module Wsjrdp2027
  # Folds free text into what a SEPA message may carry.
  #
  # The pipeline, in this order:
  #
  #   1. normalize to NFC, so a decomposed umlaut is one character again,
  #   2. the German replacements below -- "ä" becomes "ae", not "a",
  #   3. Stringex::Unidecoder for everything else non-ASCII ("ș" -> "s",
  #      "€" -> "EU", "…" -> "..."),
  #   4. every remaining character outside ALLOWED becomes "?".
  #
  # ALLOWED is the SEPA basic character set: letters, digits, space and
  # / - ? : ( ) . , ' + -- anything else (%, &, #, *, _, @, ", ...) is a "?".
  # Nothing is truncated here; #limit does that where a field has a length.
  #
  # See doc/typst_documents.md.
  module SepaText
    # Applied before the unidecoder, which would otherwise drop the diaeresis
    # and turn "Grösse"/"Größe" apart.
    GERMAN = {
      "Ä" => "Ae", "Ö" => "Oe", "Ü" => "Ue",
      "ä" => "ae", "ö" => "oe", "ü" => "ue",
      "ß" => "ss", "ẞ" => "SS"
    }.freeze

    ALLOWED = %r{[A-Za-z0-9 /\-?:().,'+]}
    FALLBACK = "?"

    class << self
      def transliterate(text)
        folded = Stringex::Unidecoder.decode(replace_german(text.to_s.unicode_normalize(:nfc)))
        folded.each_char.map { |char| ALLOWED.match?(char) ? char : FALLBACK }.join
      end

      def limit(text, max)
        transliterate(text)[0, max].to_s
      end

      private

      def replace_german(text) = text.gsub(Regexp.union(GERMAN.keys), GERMAN)
    end
  end
end
