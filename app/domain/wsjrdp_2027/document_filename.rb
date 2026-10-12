# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027
  # The file name of a stored document (doc/wsjrdp/documents.md):
  #
  #   <YYYY-mm-dd-HH-MM-SS>[_<k>]--<subject_id>-<key>[-<n>][--<secondary_key>[-<m>]][~<derivation_key>][.<ext>]
  #
  # - k: only when the name without it is taken (1, 2, ...);
  # - n, m: key_number and secondary_key_number, only when above 0;
  # - the secondary part is written when secondary_key is set or m is above 0
  #   (an empty secondary_key with m = 2 gives "<key>---2");
  # - ext: as given, else what extension_from_filename or extension_for_type
  #   find, else none.
  #
  # With only key set this is the name of the registration uploads, e.g.
  # "2026-10-11-14-03-07--791-medical.pdf". Keys contain no "." and the
  # separators "--" and "~" never occur inside a key, so every name parses
  # back (parse).
  module DocumentFilename
    TIMESTAMP_FORMAT = "%Y-%m-%d-%H-%M-%S"
    KEY_MAX_LENGTH = 40
    EXTENSION_MAX_LENGTH = 20

    # The extensions taken from an uploaded file name, and the one per
    # content type when the name has none of them (the first one listed).
    EXTENSION_TYPES = {
      "pdf" => %w[application/pdf],
      "txt" => %w[text/plain],
      "csv" => %w[text/csv],
      "xml" => %w[application/xml text/xml],
      "json" => %w[application/json],
      "doc" => %w[application/msword],
      "docx" => %w[application/vnd.openxmlformats-officedocument.wordprocessingml.document],
      "xls" => %w[application/vnd.ms-excel],
      "xlsx" => %w[application/vnd.openxmlformats-officedocument.spreadsheetml.sheet],
      "odt" => %w[application/vnd.oasis.opendocument.text],
      "ods" => %w[application/vnd.oasis.opendocument.spreadsheet],
      "eml" => %w[message/rfc822],
      "msg" => %w[application/vnd.ms-outlook],
      "jpg" => %w[image/jpeg],
      "jpeg" => [],
      "png" => %w[image/png],
      "gif" => %w[image/gif],
      "webp" => %w[image/webp],
      "heic" => %w[image/heic],
      "tif" => %w[image/tiff],
      "tiff" => [],
      "zip" => %w[application/zip],
      "gz" => %w[application/gzip application/x-gzip],
      "tar" => %w[application/x-tar],
      "bz2" => %w[application/x-bzip2],
      "xz" => %w[application/x-xz],
      "7z" => %w[application/x-7z-compressed]
    }.freeze
    KNOWN_EXTENSIONS = EXTENSION_TYPES.keys.freeze
    TYPE_EXTENSIONS = EXTENSION_TYPES.each_with_object({}) do |(extension, types), map|
      types.each { |type| map[type] ||= extension }
    end.freeze

    NAME_FORMAT = /\A(?<timestamp>\d{4}-\d{2}-\d{2}-\d{2}-\d{2}-\d{2})(?:_(?<suffix>[1-9]\d*))?--(?<subject_id>\d+)-(?<keys>[^.]+)(?:\.(?<ext>.+))?\z/
    PART_FORMAT = /\A(?<key>.*?)(?:-(?<number>[1-9]\d*))?\z/
    EXTENSION_FORMAT = /\A[a-z0-9]+(?:\.[a-z0-9]+)*\z/

    module_function

    # Whether key may be a key, a secondary_key or a derivation_key: a-z,
    # 0-9, "-" and "_", starting with a letter, at most 40 characters, no
    # "--" or "__", no "-" or "_" at the end and no "-<digits>" at the end.
    def valid_key?(key) = key_error(key).nil?

    # Why key is no valid key (a symbol), nil when it is one.
    def key_error(key)
      key = key.to_s
      if key.empty? then :blank
      elsif key.length > KEY_MAX_LENGTH then :too_long
      elsif !key.match?(/\A[a-z][a-z0-9_-]*\z/) then :invalid_characters
      elsif key.include?("--") || key.include?("__") then :double_separator
      elsif key.end_with?("-", "_") then :trailing_separator
      elsif key.match?(/-\d+\z/) then :trailing_number
      end
    end

    # Why ext is no valid extension (a symbol), nil when it is one: a-z, 0-9
    # and ".", at most 20 characters, no "..", no "." at either end.
    def extension_error(ext)
      ext = ext.to_s
      if ext.empty? then :blank
      elsif ext.length > EXTENSION_MAX_LENGTH then :too_long
      elsif !ext.match?(EXTENSION_FORMAT) then :invalid
      end
    end

    # The longest run of known extensions at the end of an uploaded file
    # name that fits into 20 characters, lowercased; nil when there is none.
    # "Scan.final.v2.PDF.tar.gz" gives "pdf.tar.gz".
    def extension_from_filename(filename)
      parts = File.basename(filename.to_s).downcase.split(".", -1)
      run = []
      parts.drop(1).reverse_each do |part|
        break unless KNOWN_EXTENSIONS.include?(part)
        break if (run + [part]).join(".").length > EXTENSION_MAX_LENGTH

        run.unshift(part)
      end
      run.empty? ? nil : run.join(".")
    end

    # The extension of a content type, nil for one not in the list.
    def extension_for_type(content_type) = TYPE_EXTENSIONS[content_type.to_s.split(";").first.to_s.strip.downcase]

    def build(timestamp:, subject_id:, key:, key_number: 0, secondary_key: "", secondary_key_number: 0,
      derivation_key: nil, ext: nil, suffix: nil)
      name = timestamp.strftime(TIMESTAMP_FORMAT)
      name += "_#{suffix}" if suffix.to_i.positive?
      name += "--#{Integer(subject_id)}-#{part(key, key_number)}"
      if secondary_key.to_s != "" || secondary_key_number.to_i.positive?
        name += "--#{part(secondary_key, secondary_key_number)}"
      end
      name += "~#{derivation_key}" if derivation_key.to_s != ""
      name += ".#{ext}" if ext.to_s != ""
      name
    end

    # The parts of a name as build takes them (timestamp as the string of the
    # name), nil for a name not of this form.
    def parse(name)
      match = NAME_FORMAT.match(name.to_s)
      return nil unless match

      keys, derivation_key, rest = match[:keys].split("~", 3)
      return nil if rest || derivation_key == ""

      first, second, rest = keys.split("--", 3)
      return nil if rest

      key, key_number = split_part(first)
      secondary_key, secondary_key_number = second ? split_part(second) : ["", 0]
      return nil unless valid_key?(key)
      return nil if second && !valid_secondary?(secondary_key, secondary_key_number)
      return nil if derivation_key && !valid_key?(derivation_key)
      return nil if match[:ext] && extension_error(match[:ext])

      {timestamp: match[:timestamp], suffix: match[:suffix].to_i, subject_id: match[:subject_id].to_i,
       key: key, key_number: key_number, secondary_key: secondary_key,
       secondary_key_number: secondary_key_number, derivation_key: derivation_key, ext: match[:ext]}
    end

    # An empty secondary key stands in a name only with its number.
    def valid_secondary?(key, number) = (key == "") ? number.positive? : valid_key?(key)

    def part(key, number) = number.to_i.positive? ? "#{key}-#{number.to_i}" : key.to_s

    def split_part(part)
      match = PART_FORMAT.match(part)
      [match[:key], match[:number].to_i]
    end
  end
end
