# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The detail partial of a finance record, declared as a block and rendered by
# fin/shared/_detail:
#
#   = fin_detail(account, ctx) do |d|
#     - d.header back: personal_accounts_path, back_label: "Zurück zu Kreditoren",
#         label: "Kreditor #{account.number}", title: account.name
#     - d.attrs :name, :iban, :bic, bic: {blank: :dash}
#     - d.raw_data do
#       - d.raw_entries :other_datev_columns, title: "DATEV Rohdaten"
#
# The block only declares (Fin::DetailBuilder); everything a section needs is
# resolved here, once per field:
#
#   value    fin_format_attr(record, attr, ctx) -- a Fin::DetailValue
#   label    the formatter's label: -> the field's label: -> captionize
#   blank    the formatter's blank: -> the field's -> the group's -> the
#            partial's -> :hide
#   layout   the group's layout: -> the partial's -> :list on a page,
#            :compact in an embedded pane
#
# A field the visibility seam (fin_attr_visible?) says no to, one whose
# formatter answers hide:, and a blank one with blank: :hide leave no row
# behind; a group without a single row renders nothing at all.
module Fin::DetailHelper
  # One resolved field, ready to render in any of the three layouts.
  Row = Data.define(:attr, :label, :value, :help, :tooltip, :blank, :span, :align, :hidden, :editable, :input, :options) do
    def hidden? = hidden

    def blank_value? = value.nil? || (value.respond_to?(:empty?) && value.empty?)

    # A row that leaves no trace: hidden, or blank in a group that hides blanks.
    def shown? = !hidden? && !(blank_value? && blank == :hide)
  end

  # Declares the sections of a detail partial and renders them. `layout:` and
  # `blank:` set this partial's defaults; `layout:` takes a Symbol or a Hash
  # {regular: ..., embedded: ...}.
  def fin_detail(record, ctx, layout: nil, blank: nil, form_url: nil)
    builder = Fin::DetailBuilder.new(capture: method(:capture))
    yield builder
    render "fin/shared/detail", record: record, ctx: ctx, sections: builder.to_sections,
      default_layout: fin_detail_layout_for(ctx, layout),
      default_blank: fin_detail_blank_mode(blank) || :hide,
      form_url: form_url,
      editing: ctx.regular?
  end

  # The layout a group falls back to: the partial's override -- a Symbol, or a
  # Hash naming one per mode -- else the mode's own default.
  def fin_detail_layout_for(ctx, override = nil)
    layout = override.is_a?(Hash) ? override[ctx.mode] : override
    return ctx.regular? ? :list : :compact if layout.nil?
    unless Fin::DetailBuilder::LAYOUTS.include?(layout)
      raise ArgumentError, "layout must be one of #{Fin::DetailBuilder::LAYOUTS.join(", ")}"
    end

    layout
  end

  # The rows of one :fields section that actually render, in declaration order.
  def fin_detail_rows(record, section, ctx, blank)
    section.items.filter_map { |field| fin_detail_row(record, field, ctx, blank) }
      .select(&:shown?)
  end

  # One field, resolved against its formatter and its options.
  def fin_detail_row(record, field, ctx, blank)
    attr = field.attr
    return nil unless fin_attr_visible?(record, attr, ctx)

    options = field.options
    detail = fin_format_attr(record, attr, ctx)
    Row.new(attr: attr, label: fin_detail_label(record, attr, detail, options),
      value: detail.value, help: detail.help || options[:help],
      tooltip: detail.tooltip || options[:tooltip],
      blank: detail.blank || options[:blank] || blank,
      span: options[:span], align: options[:align],
      hidden: detail.hide || options[:hide] || false,
      editable: options[:editable] || false, input: options[:input], options: options[:options])
  end

  # A one-off label of the formatter or of the field, else the i18n label
  # hitobito's own detail pages use.
  def fin_detail_label(record, attr, detail, options)
    detail.label || options[:label] || captionize(attr, object_class(record))
  end

  # What stands in the value column of a row: the value itself, or the marker of
  # its blank mode, plus the muted help line under it.
  def fin_detail_content(row)
    value = row.blank_value? ? fin_detail_blank_content(row.blank) : row.value
    return value if row.help.blank?

    safe_join([value, wsjrdp_row_help(row.help)].compact)
  end

  # The [key, content] lines of one entries block: the entries of the jsonb
  # column in stored order, keys verbatim and without the exclude: ones, then
  # its also: columns keyed by column name.
  def fin_detail_raw_entries(record, entries, ctx)
    source = entries.source
    return [] unless fin_attr_visible?(record, source, ctx)

    raw_ctx = ctx.with_raw_source(source)
    lines = record.public_send(source).to_h.keys
      .reject { |key| entries.exclude.include?(key.to_s) }
      .map { |key| [key.to_s, fin_raw_format(record, key, raw_ctx)] }
    lines += entries.also.map { |col| [col.to_s, fin_raw_format(record, col, ctx)] }
    fin_detail_raw_lines(lines, entries.blank || :hide)
  end

  # The entries blocks of a raw area that carry something: [title, lines] per
  # d.raw_entries, in declaration order. A block without a single shown entry
  # drops out, and an area without a single block renders nothing.
  def fin_detail_raw_blocks(record, section, ctx)
    section.items.filter_map do |entries|
      lines = fin_detail_raw_entries(record, entries, ctx)
      [entries.title, lines] if lines.any?
    end
  end

  # The open state of a raw area: open on the record's own page, collapsed in
  # an embedded pane -- unless the area says so itself (d.raw_data open:).
  def fin_detail_raw_area_open?(section, ctx)
    open = section.options[:open]
    open.nil? ? ctx.regular? : open
  end

  # The little real CSS the kit needs -- the label typography of the :list
  # layout, selected by the .fin-detail-list class on its dl. Emitted once per
  # response on the first detail (project convention: view-local styles with an
  # ivar once-guard), so a page full of detail panes carries one style block.
  def fin_detail_styles
    # rubocop:disable Rails/HelperInstanceVariable -- deliberate response-local
    # once-guard (see comment above), not view state.
    return "".html_safe if @fin_detail_styles_emitted
    @fin_detail_styles_emitted = true
    # rubocop:enable Rails/HelperInstanceVariable
    render "fin/shared/detail_styles"
  end

  # Wraps the block in a form when `form_url` is present, yielding the form
  # builder; otherwise yields nil and captures the block output as-is. In
  # regular mode (editing: true) turbo is disabled for full-page submit; in
  # embedded mode the form submits inside its turbo frame.
  def fin_detail_form_tag(record, form_url, editing:)
    if form_url
      data = {"fin-editing": editing.to_s}
      data[:turbo] = false if editing
      form_with(model: record, url: form_url, method: :patch, data: data) { |f| yield f }
    else
      capture { yield nil }
    end
  end

  def fin_detail_edit_field(f, row)
    case row.input
    when :text
      f.text_field row.attr, class: "form-control form-control-sm", style: "max-width: 20ch"
    when :check_box
      content_tag(:div, class: "form-check") do
        f.check_box(row.attr, class: "form-check-input")
      end
    when :select
      f.select row.attr, row.options, {include_blank: false},
        class: "form-select form-select-sm", style: "max-width: 24ch"
    else
      content_tag(:div, class: "input-group input-group-sm", style: "max-width: 16ch") do
        f.number_field(row.attr, step: 0.01, class: "form-control form-control-sm") +
          content_tag(:span, "€", class: "input-group-text")
      end
    end
  end

  # Save / cancel buttons for the editable detail. In regular mode the standard
  # form_buttons with a cancel link; in embedded mode a JS cancel that resets the
  # form and toggles back to display mode.
  def fin_detail_edit_actions(f, editing)
    if editing
      content_tag(:div, class: "fin-edit-actions p-2 border-top") do
        form_buttons(f, cancel_url: request.path)
      end
    else
      content_tag(:div, class: "fin-edit-actions p-2 border-top") do
        submit = f.button("Speichern", class: "btn btn-sm btn-primary mt-2", data: {disable: true})
        cancel = content_tag(:button, "Abbrechen", type: "button",
          class: "btn btn-sm btn-link mt-2",
          onclick: "var form=this.closest('[data-fin-editing]');form.reset();form.dataset.finEditing='false'")
        content_tag(:div, class: "btn-toolbar") { submit + cancel }
      end
    end
  end

  private

  def fin_detail_blank_mode(blank)
    return blank if blank.nil? || Fin::DetailValue::BLANK_MODES.include?(blank)

    raise ArgumentError, "blank must be one of #{Fin::DetailValue::BLANK_MODES.join(", ")}"
  end

  def fin_detail_blank_content(mode)
    case mode
    when :dash then content_tag(:span, "—", class: "text-muted")
    when :unset then content_tag(:span, t("fin.detail.unset"), class: "text-muted small")
    end
  end

  # Drops the entries a raw block does not show and renders the blank ones the
  # way its blank mode asks for.
  def fin_detail_raw_lines(entries, blank)
    entries.filter_map do |key, detail|
      next if detail.hide

      mode = detail.blank || blank
      next if detail.blank_value? && mode == :hide

      [key, detail.blank_value? ? fin_detail_blank_content(mode) : detail.value]
    end
  end
end
