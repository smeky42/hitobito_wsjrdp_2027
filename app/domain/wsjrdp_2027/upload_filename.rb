# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027
  # The name a document keeps of its file (WsjrdpDocument#filename). For an
  # upload it comes from the uploader's browser, as it likes (the multipart
  # header; Rack keeps its last path part). It is only ever shown -- the file
  # lies under a name of our own (DocumentFilename) --, and it is checked
  # and normalized first (doc/wsjrdp/documents.md, "File names"):
  #
  # 1. A name as given of MAX_GIVEN_BYTES bytes or more is refused -- an
  #    early way out, told as too long like step 4.
  # 2. A name that is no valid UTF-8, or holds a control character (Unicode
  #    category Cc, NUL among them), or one of FORBIDDEN -- U+202E
  #    (RIGHT-TO-LEFT OVERRIDE, which makes a name like "rechnung" U+202E
  #    "fdp.exe" read "rechnungexe.pdf"), "/" or a backslash -- is refused
  #    (#refusal; which of FORBIDDEN: #forbidden_characters).
  # 3. It is normalized (#normalize): Unicode NFC; the characters Windows
  #    does not allow in a file name (< > : " | ? *), and those
  #    ActiveStorage::Filename#sanitized replaces besides (% $ ;), become
  #    "-"; no leading white space, no trailing white space or dots (Windows
  #    drops them), white space inside stays; a name Windows reserves (CON,
  #    PRN, AUX, NUL, COM0-9, LPT0-9, also with an extension) gets "_" after
  #    it; nothing left: the fallback. The other directional marks stay:
  #    Hebrew and Arabic names need them.
  # 4. A normalized name of more than MAX_BYTES bytes is refused -- never
  #    shortened.
  #
  # Lengths are bytes of UTF-8 (String#bytesize, at hand without counting):
  # 255 bytes are never more than the 255 UTF-16 units Windows allows in a
  # name, nor than the 255 bytes of Linux file systems. A normalized name is
  # one ActiveStorage::Filename#sanitized leaves as it is.
  module UploadFilename
    MAX_GIVEN_BYTES = 500
    MAX_BYTES = 255
    REPLACED = %r{[<>:"|?*%$;]}
    # The characters refused in a name, by how a message names them.
    FORBIDDEN = {"\u202E" => "U+202E", "/" => "/", "\\" => "\\"}.freeze
    RESERVED = /\A(?:CON|PRN|AUX|NUL|COM[0-9¹²³]|LPT[0-9¹²³])(?=\.|\z)/i
    FALLBACK = "upload"
    # How many characters of a refused name a message shows (#display).
    DISPLAY_LENGTH = 60

    module_function

    # Why a name as given is refused before it is normalized (steps 1 and
    # 2): :too_long, :invalid_encoding, :control_character,
    # :forbidden_characters; nil when it is not.
    def refusal(name)
      name = name.to_s
      return :too_long if name.bytesize >= MAX_GIVEN_BYTES

      name = utf8(name)
      return :invalid_encoding unless name.valid_encoding?
      return :control_character if name.match?(/\p{Cc}/)

      :forbidden_characters if forbidden_characters(name).any?
    end

    # The FORBIDDEN characters a name holds, as a message names them.
    def forbidden_characters(name)
      name = utf8(name.to_s)
      return [] unless name.valid_encoding?

      FORBIDDEN.filter_map { |character, shown| shown if name.include?(character) }
    end

    # What a message about a refused name interpolates (the errors of
    # :filename, WsjrdpDocument).
    def error_options(name) = {max: MAX_BYTES, characters: forbidden_characters(name).to_sentence}

    # The name normalized (step 3); fallback for a name with nothing left.
    # For a name refusal has nothing against.
    def normalize(name, fallback: FALLBACK)
      name = utf8(name.to_s).unicode_normalize(:nfc).gsub(REPLACED, "-")
      name = name.strip.sub(/[\s.]+\z/, "")
      name = name.sub(RESERVED) { |reserved| "#{reserved}_" }
      name.empty? ? fallback : name
    end

    # Why a name is no name a document keeps (all steps): refusal's reasons,
    # :too_long, or :not_normalized; nil when it is one.
    def problem(name)
      refusal(name) ||
        (:too_long if name.bytesize > MAX_BYTES) ||
        (:not_normalized unless normalize(name, fallback: nil) == name)
    end

    # The base of the fallback for a document's keys, after its name on the
    # file system: "upload-<key>[-<key_number>][-<secondary_key>
    # [-<secondary_key_number>]]"; FALLBACK without a key.
    def fallback_for(key:, key_number: 0, secondary_key: "", secondary_key_number: 0)
      return FALLBACK if key.blank?

      parts = [FALLBACK, key]
      parts << key_number if key_number.to_i.positive?
      if secondary_key.present?
        parts << secondary_key
        parts << secondary_key_number if secondary_key_number.to_i.positive?
      end
      parts.join("-")
    end

    # A name as given, to show in a message whatever it holds: ASCII letters
    # and digits, space and . - _ ( ) as they are, any other character as
    # \u{XXXX}, any invalid byte as \xXX; at most DISPLAY_LENGTH characters
    # of that, "…" after a shortened one. Holds nothing HTML could read.
    def display(name)
      shown = utf8(name.to_s).scrub { |bytes| bytes.bytes.map { |byte| format("\\x%02X", byte) }.join }
        .each_char.map { |char| char.match?(/\A[A-Za-z0-9 .\-_()\\]\z/) ? char : format("\\u{%X}", char.ord) }.join
      (shown.length > DISPLAY_LENGTH) ? "#{shown[0, DISPLAY_LENGTH]}…" : shown
    end

    # The bytes read as UTF-8 (a copy; a name given as binary keeps its
    # bytes).
    def utf8(name)
      return name if name.encoding == Encoding::UTF_8

      name.dup.force_encoding(Encoding::UTF_8)
    end
  end
end
