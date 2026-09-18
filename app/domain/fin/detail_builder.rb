# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Block-based collector behind `= fin_detail(record, ctx) do |d| ... end`
# (Fin::DetailHelper): the block DECLARES the sections of a finance detail
# partial, the helper renders them afterwards through fin/shared/_detail. Two
# phases, like Wsjrdp::ExpandableTableBuilder -- no HTML is produced inside the
# block except for #custom, whose block the helper captures.
#
#   = fin_detail(account, ctx) do |d|
#     - d.header back: personal_accounts_path, back_label: "Zurück zu Kreditoren",
#         label: "Kreditor #{account.number}", title: account.name
#     - d.attrs :name, :short_name, :aliases
#     - d.attrs :iban, :bic, bic: {blank: :dash}
#     - d.raw_data do
#       - d.raw_entries :other_datev_columns, title: "DATEV Rohdaten"
#     - d.bookings rows, show_all_path: path, all_label: "In Buchungen-Ansicht öffnen"
#
# One section per call, in declaration order; #section opens a titled group that
# the #attrs / #attr calls inside its block append to, #raw_data a collapsible
# raw area that the #raw_entries calls inside its block append to. Pure Ruby:
# the builder knows nothing of Rails, which is what lets its spec run standalone.
#
# A host that shows the same partial with FEWER fields -- the group's booking
# page next to /fin's -- hands `only:` a list of attribute keys and section keys
# instead of writing a second partial; the sections that carry no attributes of
# their own (#custom, #raw_data, #bookings) are named in it by their own `key:`.
class Fin::DetailBuilder
  # A declared section. `items` holds the fields of a :fields section and the
  # entries blocks of a :raw_data one, `html` the captured HTML of a :custom
  # section, `options` everything a kind needs of its own (the header's links,
  # the raw area's open state, the bookings rows), `key` the name a `only:` list
  # addresses a KEYED_KINDS section by.
  Section = Data.define(:kind, :title, :layout, :blank, :items, :html, :options, :key) do
    # Data has no per-member defaults; a section names what its kind needs and
    # leaves the rest alone.
    def initialize(kind:, title: nil, layout: nil, blank: nil, items: nil, html: nil,
      options: {}, key: nil)
      super
    end
  end

  # One field of a :fields section: the attribute and its per-field options.
  Field = Data.define(:attr, :options)

  # One entries block of a :raw_data section: the jsonb column it lists, its
  # title and what it adds to / leaves out of the column's keys.
  RawEntries = Data.define(:source, :title, :also, :exclude, :blank)

  # The section kinds fin/shared/_detail dispatches on.
  KINDS = %i[header fields raw_data custom bookings].freeze

  # The kinds a `only:` list addresses as a WHOLE, by the section's own `key:`
  # -- they carry no attributes of their own. A :fields section is addressed
  # through the attributes inside it and the :header always stays.
  KEYED_KINDS = %i[raw_data custom bookings].freeze

  # The field layouts (fin/shared/_detail_group): the core list, the compact
  # rows of an embedded pane, the cells with span/align.
  LAYOUTS = %i[list compact grid].freeze

  # Keys of #attrs that configure the GROUP; every other key names one of the
  # listed attributes and carries its per-field options.
  GROUP_KEYS = %i[layout title blank].freeze

  # What a per-field option hash may say. `value` is not among them: a field's
  # value comes from the record through its formatter, never from the partial.
  # `extra` names a helper that renders one more control beside the field's
  # input (Fin::DetailHelper#fin_detail_edit_field).
  FIELD_KEYS = %i[label help tooltip blank hide span align editable input options extra].freeze

  # `capture` turns the block of #custom into HTML. The helper hands in the
  # view's own capture; on its own the builder just calls the block, so a
  # standalone spec sees what the block returns.
  #
  # `only` is the FIELD LIST of a host that shows the same partial with fewer
  # fields (the group's booking page): attribute keys and section keys, as
  # Symbols or Strings. nil -- the normal case -- shows everything the block
  # declares. See #to_sections for what the list does.
  def initialize(capture: nil, only: nil)
    @capture = capture || ->(&block) { block.call }
    @only = only.nil? ? nil : Array(only).map(&:to_s).uniq.freeze
    @sections = []
    @open_section = nil
    @open_raw = nil
  end

  # The regular page's header: back link, the h1 -- its technical `label:` muted
  # and the record's `title:` in normal weight -- and an optional toolbar.
  # Rendered in :regular mode only; an embedded pane gets its header line from
  # the table widget.
  # `back:` is optional: a host that puts a record on its OWN route -- the
  # group's booking page, reached from the tab it would link back to -- passes
  # nil and the header renders no link at all.
  def header(label:, back: nil, back_label: nil, title: nil, toolbar: nil)
    add(Section.new(kind: :header, title: title,
      options: {back: back, back_label: back_label, label: label, toolbar: toolbar}))
  end

  # One group of fields, in the given order. GROUP_KEYS configure the group,
  # every other key names one of the listed attributes and gives it its own
  # options (`bic: {blank: :dash}`, `iban: {label: "IBAN", span: 2}`).
  def attrs(*attrs, **options)
    group, per_field = split_options(options, attrs)
    fields = attrs.map { |attr| build_field(attr, per_field.fetch(attr.to_sym, {})) }
    if @open_section
      raise ArgumentError, "#{GROUP_KEYS.join(", ")} belong to d.section here" if group.any?
      @open_section.items.concat(fields)
    else
      add(fields_section(**group, items: fields))
    end
    nil
  end

  # A single field: a group of its own, or one more field of the open #section.
  # All options are per-field ones here.
  def attr(attr, **field_options)
    field = build_field(attr, field_options)
    if @open_section
      @open_section.items << field
    else
      add(fields_section(items: [field]))
    end
    nil
  end

  # A titled group; the #attrs / #attr calls inside the block append to it.
  def section(title: nil, layout: nil, blank: nil)
    raise ArgumentError, "d.section needs a block" unless block_given?
    raise ArgumentError, "d.section cannot be nested" if @open_section

    @open_section = add(fields_section(title: title, layout: layout, blank: blank, items: []))
    begin
      yield self
    ensure
      @open_section = nil
    end
    nil
  end

  # A collapsible raw area; the #raw_entries calls inside the block become its
  # titled entries blocks. `title:` heads the area -- nil leaves it to the
  # renderer's default -- and `open:` its state: nil follows the mode (open on
  # the record's own page, collapsed in an embedded pane), true / false force
  # it. `key:` is the name a `only:` list addresses the area by. A partial may
  # declare several areas, each rendering where it stands.
  def raw_data(title: nil, open: nil, key: nil)
    raise ArgumentError, "d.raw_data needs a block" unless block_given?
    raise ArgumentError, "d.raw_data cannot be nested" if @open_raw
    raise ArgumentError, "d.raw_data cannot be opened inside d.section" if @open_section

    @open_raw = add(Section.new(kind: :raw_data, title: title, items: [],
      options: {open: open}, key: key))
    begin
      yield self
    ensure
      @open_raw = nil
    end
    nil
  end

  # One entries block of the open #raw_data area, over one jsonb column: its
  # entries as monospace `key: value` lines, keys verbatim as the export wrote
  # them. `also:` appends regular columns to the block, keyed by their column
  # name; `exclude:` names keys of the source the block leaves out, compared
  # verbatim against its keys.
  def raw_entries(source, title:, also: [], exclude: [], blank: :hide)
    raise ArgumentError, "d.raw_entries belongs inside d.raw_data" unless @open_raw

    @open_raw.items << RawEntries.new(source: source.to_sym, title: title,
      also: Array(also).map(&:to_sym), exclude: Array(exclude).map(&:to_s),
      blank: check_blank(blank))
    nil
  end

  # Hand-written HAML (links, forms, a model's own widgets). The block is
  # captured right here, so the section carries finished HTML. `key:` is the
  # name a `only:` list addresses the section by.
  def custom(title: nil, key: nil, &block)
    raise ArgumentError, "d.custom needs a block" unless block

    add(Section.new(kind: :custom, title: title, html: @capture.call(&block), key: key))
    nil
  end

  # The embedded, paged bookings list of a Buchhaltung detail
  # (fin/bookings/_embedded). `key:` is the name a `only:` list addresses it by.
  def bookings(rows, show_all_path:, all_label:, key: nil)
    add(Section.new(kind: :bookings,
      options: {rows: rows, show_all_path: show_all_path, all_label: all_label}, key: key))
    nil
  end

  # The declared sections in declaration order -- the declaration phase is over,
  # so the field lists are frozen.
  #
  # With a `only:` list the partial is reduced to what the host asked for: a
  # field whose attribute the list does not name falls away, a field group left
  # without a single field falls away with it, and a KEYED_KINDS section is kept
  # only when the list names its `key:`. The header always stays -- it is the
  # page's own frame, not content. Without a list nothing is dropped.
  def to_sections
    sections = @sections.map { |s| s.items ? s.with(items: s.items.freeze) : s }
    return sections if @only.nil?

    sections.filter_map { |section| shown_section(section) }
  end

  private

  # One section as a `only:` list leaves it, or nil when it leaves nothing. A
  # keyed kind WITHOUT a `key:` could never appear in such a list, so it would
  # vanish silently: that is a declaration mistake and says so.
  def shown_section(section)
    case section.kind
    when :header then section
    when :fields
      kept = section.items.select { |field| @only.include?(field.attr.to_s) }
      section.with(items: kept.freeze) if kept.any?
    else
      raise ArgumentError, "#{section_name(section)} needs a key: to be named in only:" if section.key.nil?

      section if @only.include?(section.key.to_s)
    end
  end

  def section_name(section)
    title = section.title.to_s
    title.empty? ? "d.#{section.kind}" : "d.#{section.kind} (#{title})"
  end

  def add(section)
    @sections << section
    section
  end

  def fields_section(title: nil, layout: nil, blank: nil, items: [])
    Section.new(kind: :fields, title: title, layout: check_layout(layout),
      blank: check_blank(blank), items: items)
  end

  def build_field(attr, options)
    unknown = options.keys - FIELD_KEYS
    if unknown.any?
      raise ArgumentError, "unknown field option(s) #{unknown.join(", ")} for #{attr}; " \
                           "known: #{FIELD_KEYS.join(", ")}"
    end
    check_blank(options[:blank])
    Field.new(attr: attr.to_sym, options: options)
  end

  # Splits the keywords of #attrs into the group's own settings and the
  # per-field option hashes. A per-field key must name one of the listed
  # attributes, otherwise the options would silently apply to nothing.
  def split_options(options, attrs)
    group = options.slice(*GROUP_KEYS)
    per_field = options.except(*GROUP_KEYS)
    listed = attrs.map(&:to_sym)
    unknown = per_field.keys - listed
    if unknown.any?
      raise ArgumentError, "#{unknown.join(", ")} is not among the attributes of this group " \
                           "(#{listed.join(", ")})"
    end
    [group, per_field]
  end

  def check_layout(layout)
    return layout if layout.nil? || LAYOUTS.include?(layout)

    raise ArgumentError, "layout must be one of #{LAYOUTS.join(", ")}"
  end

  def check_blank(blank)
    return blank if blank.nil? || Fin::DetailValue::BLANK_MODES.include?(blank)

    raise ArgumentError, "blank must be one of #{Fin::DetailValue::BLANK_MODES.join(", ")}"
  end
end
