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
class Fin::DetailBuilder
  # A declared section. `items` holds the fields of a :fields section and the
  # entries blocks of a :raw_data one, `html` the captured HTML of a :custom
  # section, `options` everything a kind needs of its own (the header's links,
  # the raw area's open state, the bookings rows).
  Section = Data.define(:kind, :title, :layout, :blank, :items, :html, :options)

  # One field of a :fields section: the attribute and its per-field options.
  Field = Data.define(:attr, :options)

  # One entries block of a :raw_data section: the jsonb column it lists, its
  # title and what it adds to / leaves out of the column's keys.
  RawEntries = Data.define(:source, :title, :also, :exclude, :blank)

  # The section kinds fin/shared/_detail dispatches on.
  KINDS = %i[header fields raw_data custom bookings].freeze

  # The field layouts (fin/shared/_detail_group): the core list, the compact
  # rows of an embedded pane, the cells with span/align.
  LAYOUTS = %i[list compact grid].freeze

  # Keys of #attrs that configure the GROUP; every other key names one of the
  # listed attributes and carries its per-field options.
  GROUP_KEYS = %i[layout title blank].freeze

  # What a per-field option hash may say. `value` is not among them: a field's
  # value comes from the record through its formatter, never from the partial.
  FIELD_KEYS = %i[label help tooltip blank hide span align editable input options].freeze

  # `capture` turns the block of #custom into HTML. The helper hands in the
  # view's own capture; on its own the builder just calls the block, so a
  # standalone spec sees what the block returns.
  def initialize(capture: nil)
    @capture = capture || ->(&block) { block.call }
    @sections = []
    @open_section = nil
    @open_raw = nil
  end

  # The regular page's header: back link, the h1 -- its technical `label:` muted
  # and the record's `title:` in normal weight -- and an optional toolbar.
  # Rendered in :regular mode only; an embedded pane gets its header line from
  # the table widget.
  def header(back:, back_label:, label:, title: nil, toolbar: nil)
    add(Section.new(kind: :header, title: title, layout: nil, blank: nil, items: nil,
      html: nil, options: {back: back, back_label: back_label, label: label,
                           toolbar: toolbar}))
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
  # it. A partial may declare several areas, each rendering where it stands.
  def raw_data(title: nil, open: nil)
    raise ArgumentError, "d.raw_data needs a block" unless block_given?
    raise ArgumentError, "d.raw_data cannot be nested" if @open_raw
    raise ArgumentError, "d.raw_data cannot be opened inside d.section" if @open_section

    @open_raw = add(Section.new(kind: :raw_data, title: title, layout: nil, blank: nil,
      items: [], html: nil, options: {open: open}))
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
  # captured right here, so the section carries finished HTML.
  def custom(title: nil, &block)
    raise ArgumentError, "d.custom needs a block" unless block

    add(Section.new(kind: :custom, title: title, layout: nil, blank: nil, items: nil,
      html: @capture.call(&block), options: {}))
    nil
  end

  # The embedded, paged bookings list of a Buchhaltung detail
  # (fin/bookings/_embedded).
  def bookings(rows, show_all_path:, all_label:)
    add(Section.new(kind: :bookings, title: nil, layout: nil, blank: nil, items: nil,
      html: nil,
      options: {rows: rows, show_all_path: show_all_path, all_label: all_label}))
    nil
  end

  # The declared sections in declaration order -- the declaration phase is over,
  # so the field lists are frozen.
  def to_sections
    @sections.map { |section| section.items ? section.with(items: section.items.freeze) : section }
  end

  private

  def add(section)
    @sections << section
    section
  end

  def fields_section(title: nil, layout: nil, blank: nil, items: [])
    Section.new(kind: :fields, title: title, layout: check_layout(layout),
      blank: check_blank(blank), items: items, html: nil, options: {})
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
