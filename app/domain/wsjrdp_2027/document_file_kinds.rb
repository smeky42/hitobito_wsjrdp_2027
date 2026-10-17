# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027
  # The file kinds the form of a document kind offers to add at once
  # (document_management/document_kinds/_form, "Dateiarten hinzufügen"):
  # a label, an icon and the extensions; the content types come from Marcel,
  # as an upload's are found (Wsjrdp2027::DocumentStore). An extension Marcel
  # does not know by name -- the compound ones of archives -- names its type
  # in `extension_types:`, as Marcel finds it in the content. TYPE_LABELS
  # names the types for the chips' tooltips, which show the extensions of a
  # kind grouped by their type.
  module DocumentFileKinds
    LIST = [
      {key: "pdf", label: "PDF", icon: :"file-pdf", extensions: %w[pdf]},
      {key: "images", label: "Bilder", icon: :"file-image", extensions: %w[jpg jpeg png heic webp]},
      # Word and OpenDocument, with their templates. No office kind has the
      # macro formats (docm, xlsm, pptm, ...).
      {key: "word_processing", label: "Textverarbeitung", icon: :"file-word",
       extensions: %w[doc docx dot dotx odt ott]},
      # Excel and OpenDocument, with their templates.
      {key: "spreadsheets", label: "Tabellenkalkulation", icon: :"file-excel", extensions: %w[xls xlsx xlt xltx ods ots]},
      # PowerPoint and OpenDocument, with templates and slide shows.
      {key: "presentations", label: "Präsentationen", icon: :"file-powerpoint",
       extensions: %w[ppt pptx pot potx pps ppsx odp otp]},
      {key: "mail", label: "E-Mail", icon: :envelope, extensions: %w[eml msg]},
      {key: "plain_text", label: "Reiner Text", icon: :"file-alt", extensions: %w[txt md markdown]},
      {key: "archives", label: "Archiv", icon: :"file-archive",
       extensions: %w[zip tar tar.gz tgz tar.bz2 tar.zstd tar.zst],
       extension_types: {"tar.gz" => "application/gzip", "tar.bz2" => "application/x-bzip2",
                         "tar.zstd" => "application/zstd", "tar.zst" => "application/zstd"}}
    ].freeze

    # Short names of the types, for the tooltips.
    TYPE_LABELS = {
      "application/pdf" => "PDF",
      "image/jpeg" => "JPEG", "image/png" => "PNG", "image/heic" => "HEIC (iPhone)", "image/webp" => "WebP",
      "application/msword" => "Word 97–2003, auch Vorlage",
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document" => "Word",
      "application/vnd.openxmlformats-officedocument.wordprocessingml.template" => "Word-Vorlage",
      "application/vnd.oasis.opendocument.text" => "OpenDocument-Text",
      "application/vnd.oasis.opendocument.text-template" => "OpenDocument-Textvorlage",
      "application/vnd.ms-excel" => "Excel 97–2003, auch Vorlage",
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" => "Excel",
      "application/vnd.openxmlformats-officedocument.spreadsheetml.template" => "Excel-Vorlage",
      "application/vnd.oasis.opendocument.spreadsheet" => "OpenDocument-Tabelle",
      "application/vnd.oasis.opendocument.spreadsheet-template" => "OpenDocument-Tabellenvorlage",
      "application/vnd.ms-powerpoint" => "PowerPoint 97–2003, auch Vorlage und Bildschirmpräsentation",
      "application/vnd.openxmlformats-officedocument.presentationml.presentation" => "PowerPoint",
      "application/vnd.openxmlformats-officedocument.presentationml.template" => "PowerPoint-Vorlage",
      "application/vnd.openxmlformats-officedocument.presentationml.slideshow" => "PowerPoint-Bildschirmpräsentation",
      "application/vnd.oasis.opendocument.presentation" => "OpenDocument-Präsentation",
      "application/vnd.oasis.opendocument.presentation-template" => "OpenDocument-Präsentationsvorlage",
      "message/rfc822" => "E-Mail",
      "application/vnd.ms-outlook" => "Outlook-Nachricht",
      "text/plain" => "Text", "text/markdown" => "Markdown",
      "application/zip" => "ZIP", "application/x-tar" => "tar", "application/gzip" => "gzip-komprimiert",
      "application/x-bzip2" => "bzip2-komprimiert", "application/zstd" => "Zstandard-komprimiert"
    }.freeze

    # Short names of the types for the Typ column of the documents lists
    # (DocumentManagement::DocumentsHelper#document_type_cell).
    SHORT_LABELS = {
      "application/pdf" => "PDF",
      "image/jpeg" => "JPEG", "image/png" => "PNG", "image/heic" => "HEIC", "image/webp" => "WebP",
      "image/gif" => "GIF",
      "application/msword" => "Word",
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document" => "Word",
      "application/vnd.openxmlformats-officedocument.wordprocessingml.template" => "Word",
      "application/vnd.oasis.opendocument.text" => "ODT",
      "application/vnd.oasis.opendocument.text-template" => "ODT",
      "application/vnd.ms-excel" => "Excel",
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" => "Excel",
      "application/vnd.openxmlformats-officedocument.spreadsheetml.template" => "Excel",
      "application/vnd.oasis.opendocument.spreadsheet" => "ODS",
      "application/vnd.oasis.opendocument.spreadsheet-template" => "ODS",
      "application/vnd.ms-powerpoint" => "PowerPoint",
      "application/vnd.openxmlformats-officedocument.presentationml.presentation" => "PowerPoint",
      "application/vnd.openxmlformats-officedocument.presentationml.template" => "PowerPoint",
      "application/vnd.openxmlformats-officedocument.presentationml.slideshow" => "PowerPoint",
      "application/vnd.oasis.opendocument.presentation" => "ODP",
      "application/vnd.oasis.opendocument.presentation-template" => "ODP",
      "message/rfc822" => "E-Mail", "application/vnd.ms-outlook" => "Outlook",
      "text/plain" => "Text", "text/markdown" => "Markdown",
      "application/zip" => "ZIP", "application/x-tar" => "tar", "application/gzip" => "gzip",
      "application/x-bzip2" => "bzip2", "application/zstd" => "zstd"
    }.freeze

    module_function

    UNKNOWN_TYPE = "application/octet-stream"
    UNKNOWN_ICON = :file

    # The icon of a content type: its file kind's; for another image or
    # text that of images or plain text; else UNKNOWN_ICON.
    def icon_for(content_type)
      type = content_type.to_s
      type_icons[type] ||
        (:"file-image" if type.start_with?("image/")) ||
        (:"file-alt" if type.start_with?("text/")) ||
        UNKNOWN_ICON
    end

    # The short name of a content type, nil for one SHORT_LABELS does not
    # know.
    def short_label_for(content_type) = SHORT_LABELS[content_type.to_s]

    # Every type of a file kind with the kind's icon.
    def type_icons
      @type_icons ||= all.each_with_object({}) do |kind, icons|
        kind[:types].each { |type| icons[type] ||= kind[:icon] }
      end
    end

    # The type of an extension: the one a kind names, else Marcel's by
    # name; nil when Marcel does not know it.
    def type_for(extension)
      extension_types[extension] ||
        Marcel::MimeType.for(name: "file.#{extension}").then { |type| type unless type == UNKNOWN_TYPE }
    end

    def extension_types = LIST.each_with_object({}) { |kind, types| types.merge!(kind.fetch(:extension_types, {})) }

    # The file kinds with their content types and, for the tooltip, their
    # extensions grouped by type ({type:, label:, extensions:}).
    def all
      LIST.map do |kind|
        groups = kind[:extensions].group_by { |ext| type_for(ext) }.except(nil)
          .map { |type, extensions| {type: type, label: TYPE_LABELS[type], extensions: extensions} }
        kind.except(:extension_types).merge(types: groups.pluck(:type), groups: groups)
      end
    end
  end
end
