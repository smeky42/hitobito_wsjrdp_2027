# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The tag select: a <select multiple> that shared/wsjrdp/_tag_select_js
# turns into a TomSelect with chips and autocomplete. Each option may carry a
# description, shown beside it in the list; with `create:` (a JavaScript
# pattern) values of that form not in the list can be typed in.
#
# The page renders the script (render "shared/wsjrdp/tag_select_js"); it
# enhances every select of this kind on load, after a Turbo visit and in every
# loaded turbo frame. A hidden empty
# value goes along, so that a select left empty still sends its name.
#
# A long list of suggestions (`source:`) comes once per response as JSON
# (render "shared/wsjrdp/tag_select_sources") instead of as options of every
# select; the
# select holds only its chosen values, and the list shows the first matches.
module Wsjrdp::TagSelectHelper
  # The access entries of the document lists (Wsjrdp2027::DocumentAccess);
  # other entries of their form can be typed in.
  ACCESS_ENTRIES = (%w[person log update] + Wsjrdp2027::DocumentAccess::FINANCE_ENTRIES).freeze
  ACCESS_ENTRY_PATTERN = WsjrdpDocumentKind::ENTRY_JS_PATTERN
  # WsjrdpDocumentKind::CONTENT_TYPE_FORMAT and EXTENSION_FORMAT.
  CONTENT_TYPE_PATTERN = "^[a-z0-9][a-z0-9.+-]*/(?:\\*|[a-z0-9][a-z0-9.+-]*)$"
  EXTENSION_PATTERN = "^[a-z0-9]+(?:\\.[a-z0-9]+)*$"
  # The types every file of a family has.
  TYPE_FAMILIES = %w[application audio font image message model text video].freeze
  SOURCE_MATCHES_SHOWN = 50

  # options: [[value, description], ...]; a selected value not among them is
  # added at the end.
  def wsjrdp_tag_select(name, options, selected, create: nil, placeholder: nil, id: nil, source: nil)
    selected = Array(selected).map(&:to_s)
    all = options.map { |value, description| [value.to_s, description] }
    all += (selected - all.map(&:first)).map { |value| [value, nil] }
    option_tags = safe_join(all.map do |value, description|
      content_tag(:option, value, value: value, selected: selected.include?(value),
        data: {description: description}.compact)
    end)
    safe_join([
      hidden_field_tag(name, "", id: nil),
      select_tag(name, option_tags, multiple: true, id: id, class: "form-select form-select-sm",
        data: {wsjrdp_tag_select: true, create_pattern: create, placeholder: placeholder,
               source: source && "wsjrdp-tag-source-#{source}", max_options: (SOURCE_MATCHES_SHOWN if source)}.compact)
    ])
  end

  def wsjrdp_access_entries_select(name, selected, id: nil)
    options = ACCESS_ENTRIES.map { |entry| [entry, t("wsjrdp.access_entries.#{entry}")] }
    wsjrdp_tag_select(name, options, selected, create: ACCESS_ENTRY_PATTERN, id: id,
      placeholder: t("wsjrdp.access_entries.placeholder"))
  end

  # The statuses of a person (Settings.status), described by their names.
  def wsjrdp_status_select(name, selected, id: nil)
    options = Settings.status.to_h.map { |status, label| [status.to_s, label] }
    wsjrdp_tag_select(name, options, selected, id: id, placeholder: t("wsjrdp.access_entries.status_placeholder"))
  end

  # The content types of a kind (WsjrdpDocumentKind#content_types): Marcel's
  # types and the families ("image/*"), each with its extensions.
  def wsjrdp_content_types_select(name, selected, id: nil)
    wsjrdp_tag_select(name, [], selected, create: CONTENT_TYPE_PATTERN, id: id, source: "content-types",
      placeholder: t("wsjrdp.access_entries.placeholder"))
  end

  # The extensions of a kind (WsjrdpDocumentKind#extensions): Marcel's, each
  # with its type.
  def wsjrdp_extensions_select(name, selected, id: nil)
    wsjrdp_tag_select(name, [], selected, create: EXTENSION_PATTERN, id: id, source: "extensions",
      placeholder: t("wsjrdp.access_entries.placeholder"))
  end

  # The suggestions of the content type and extension selects, by source
  # (shared/wsjrdp/_tag_select_sources): [[value, description], ...].
  def wsjrdp_marcel_sources
    content_type = Regexp.new(CONTENT_TYPE_PATTERN)
    extension = Regexp.new(EXTENSION_PATTERN)
    types = Marcel::TYPE_EXTS.filter_map do |type, (exts, *)|
      type = type.downcase
      [type, Array(exts).first(4).map { |ext| ".#{ext}" }.join(" ")] if type.match?(content_type)
    end
    families = TYPE_FAMILIES.map { |family| ["#{family}/*", t("wsjrdp.access_entries.type_family")] }
    extensions = Marcel::EXTENSIONS.filter_map do |ext, type|
      ext = ext.downcase
      [ext, type] if ext.match?(extension)
    end
    # The compound extensions of the file kinds (tar.gz, ...) first.
    extensions = Wsjrdp2027::DocumentFileKinds.extension_types.to_a + extensions
    {"content-types" => (families + types.sort).uniq(&:first), "extensions" => extensions.sort.uniq(&:first)}
  end
end
