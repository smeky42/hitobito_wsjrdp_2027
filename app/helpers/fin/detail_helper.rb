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
#
# `editing:` picks one of three modes (EDIT_MODES): nil keeps what the kit has
# always done, false is a reading page, true the edit page. See
# doc/fin/detail_partials.md §6.
module Fin::DetailHelper
  # The kit's three edit modes, named by the `editing:` of #fin_detail:
  #
  #   nil    :auto  what the kit has always done -- the record's own page shows
  #                 the inputs, an embedded pane the inline "Bearbeiten" toggle
  #   false  :view  a READING page: no form at all, whatever `form_url:` says,
  #                 and no toggle; a blank row falls to its blank rule as usual
  #   true   :edit  the EDIT PAGE: inputs for the editable rows, the page's two
  #                 submits and the link back to the reading page
  EDIT_MODES = {nil => :auto, false => :view, true => :edit}.freeze

  # One resolved field, ready to render in any of the three layouts.
  Row = Data.define(:attr, :label, :value, :help, :tooltip, :blank, :span, :align, :hidden, :editable, :editable_field, :input, :options, :extra) do
    def hidden? = hidden

    def blank_value? = value.nil? || (value.respond_to?(:empty?) && value.empty?)

    # A row that leaves no trace: hidden, or blank in a group that hides blanks.
    #
    # Wherever the detail carries a FORM -- the edit page, and the inline toggle
    # of an embedded pane -- an editable field always stands, blank or not: that
    # is where its input goes, and where, for a viewer who may read but not
    # change it, the unset marker explains the gap. Only the reading page, which
    # has no form at all, lets a blank one fall to its blank rule.
    #
    # The test is `editable_field`, the DECLARATION that the partial counts this
    # field among the page's editable ones, not `editable`, which answers
    # whether THIS viewer may edit it.
    def shown?(editable_shown = false)
      return false if hidden?
      return true if editable_shown && editable_field

      !(blank_value? && blank == :hide)
    end
  end

  # Declares the sections of a detail partial and renders them. `layout:` and
  # `blank:` set this partial's defaults; `layout:` takes a Symbol or a Hash
  # {regular: ..., embedded: ...}. `only:` is the field list of a host that
  # shows the partial with fewer fields (Fin::DetailBuilder#to_sections); nil
  # renders everything the block declares.
  #
  # `editing:` picks the edit mode (EDIT_MODES). `edit_url:` is the edit page
  # the "Bearbeiten" button of a :view header points at, `cancel_url:` the
  # reading page the "Abbrechen" of an :edit page returns to; both render
  # nothing when they are nil.
  def fin_detail(record, ctx, layout: nil, blank: nil, form_url: nil, only: nil,
    editing: nil, edit_url: nil, cancel_url: nil)
    builder = Fin::DetailBuilder.new(capture: method(:capture), only: only)
    yield builder
    render "fin/shared/detail", record: record, ctx: ctx, sections: builder.to_sections,
      default_layout: fin_detail_layout_for(ctx, layout),
      default_blank: fin_detail_blank_mode(blank) || :hide,
      form_url: form_url,
      edit_mode: fin_detail_edit_mode(editing),
      edit_url: edit_url,
      cancel_url: cancel_url
  end

  # The edit mode of this detail (EDIT_MODES); anything but nil / true / false
  # is a declaration mistake and says so.
  def fin_detail_edit_mode(editing)
    EDIT_MODES.fetch(editing) do
      raise ArgumentError, "editing must be nil (auto), false (view) or true (edit)"
    end
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
  # `editable_shown:` is true where the detail carries a form, and an editable
  # field therefore always stands (Row#shown?).
  def fin_detail_rows(record, section, ctx, blank, editable_shown: false)
    section.items.filter_map { |field| fin_detail_row(record, field, ctx, blank) }
      .select { |row| row.shown?(editable_shown) }
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
      editable: options[:editable] || false,
      editable_field: options.key?(:editable),
      input: options[:input], options: options[:options], extra: options[:extra])
  end

  # A one-off label of the formatter or of the field, else the i18n label
  # hitobito's own detail pages use.
  def fin_detail_label(record, attr, detail, options)
    detail.label || options[:label] || captionize(attr, object_class(record))
  end

  # What stands in the value column of a row: the value itself, or the marker of
  # its blank mode, plus the muted help line under it.
  #
  # Where the detail carries a form, a blank editable field stands where its
  # input goes. Where no input is rendered -- the viewer may read but not change
  # it -- the :hide of the reading page would leave the value column empty, so
  # the unset marker takes its place and says what the gap means.
  def fin_detail_content(row, editable_shown = false)
    blank = (editable_shown && row.editable_field && row.blank == :hide) ? :unset : row.blank
    value = row.blank_value? ? fin_detail_blank_content(blank) : row.value
    return value if row.help.blank?

    safe_join([value, wsjrdp_row_help(row.help)].compact)
  end

  # The header's toolbar slot (doc/fin/detail_partials.md §9). In :view mode
  # with an edit page behind it, the "Bearbeiten" button stands in front of
  # whatever the section declared. It breaks out of the turbo frame the detail
  # sits in (`_top`): a plain link would navigate that frame and leave the
  # page's own URL behind.
  def fin_detail_header_toolbar(toolbar, edit_url, mode)
    return toolbar unless mode == :view && edit_url.present?

    button = link_to("Bearbeiten", edit_url, class: "btn btn-sm btn-outline-primary",
      data: {turbo_frame: "_top"})
    toolbar.present? ? safe_join([button, toolbar], " ") : button
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

  # The input of an editable row, plus the `extra:` control a field declares
  # next to it (a Symbol naming a helper, called with the form builder and the
  # row). The pair sits in one flex line so both stay on the same row.
  def fin_detail_edit_field(f, row)
    input = fin_detail_edit_input(f, row)
    return input if row.extra.blank?

    content_tag(:div, class: "d-flex flex-wrap align-items-center gap-2") do
      safe_join([input, public_send(row.extra, f, row)])
    end
  end

  def fin_detail_edit_input(f, row)
    case row.input
    when :text
      f.text_field row.attr, class: "form-control form-control-sm", style: "max-width: 20ch"
    when :textarea
      f.text_area row.attr, rows: 3, class: "form-control form-control-sm"
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

  # Save / cancel buttons for the editable detail. The EDIT PAGE carries its own
  # two submits and the link back to the reading page; in :auto mode the
  # record's own page keeps hitobito's form_buttons, and an embedded pane the JS
  # cancel that resets the form and toggles back to display mode.
  def fin_detail_edit_actions(f, editing, mode: :auto, cancel_url: nil)
    content_tag(:div, class: "fin-edit-actions p-2 border-top") do
      if mode == :edit
        fin_detail_edit_page_buttons(f, cancel_url)
      elsif editing
        form_buttons(f, cancel_url: request.path)
      else
        fin_detail_inline_buttons(f)
      end
    end
  end

  # The two submits of the edit page and its cancel link. Both submits post the
  # same form; only the second carries `stay`, which is what the host reads to
  # come back here instead of going on to the reading page. The cancel is a
  # link, and breaks out of the detail's turbo frame like the "Bearbeiten"
  # button does.
  def fin_detail_edit_page_buttons(f, cancel_url)
    buttons = [
      f.button("Speichern", name: "save", value: "1",
        class: "btn btn-sm btn-primary mt-2", data: {disable: true}),
      f.button("Speichern und weiter bearbeiten", name: "stay", value: "1",
        class: "btn btn-sm btn-outline-primary mt-2 ms-2", data: {disable: true})
    ]
    if cancel_url.present?
      buttons << link_to("Abbrechen", cancel_url, class: "btn btn-sm btn-link mt-2 ms-2",
        data: {turbo_frame: "_top"})
    end
    content_tag(:div, safe_join(buttons), class: "btn-toolbar")
  end

  def fin_detail_inline_buttons(f)
    submit = f.button("Speichern", class: "btn btn-sm btn-primary mt-2", data: {disable: true})
    cancel = content_tag(:button, "Abbrechen", type: "button",
      class: "btn btn-sm btn-link mt-2",
      onclick: "var form=this.closest('[data-fin-editing]');form.reset();form.dataset.finEditing='false'")
    content_tag(:div, class: "btn-toolbar") { submit + cancel }
  end

  private

  def fin_detail_blank_mode(blank)
    return blank if blank.nil? || Fin::DetailValue::BLANK_MODES.include?(blank)

    raise ArgumentError, "blank must be one of #{Fin::DetailValue::BLANK_MODES.join(", ")}"
  end

  # The marker of a blank field. "nicht gesetzt" states an absence and steps
  # further back than the muted em dash -- Bootstrap 5.2 (the core's version)
  # has no .text-body-tertiary yet, so the extra step is an inline opacity.
  def fin_detail_blank_content(mode)
    case mode
    when :dash then content_tag(:span, "—", class: "text-muted")
    when :unset
      content_tag(:span, t("fin.detail.unset"), class: "text-muted small",
        style: "opacity: .6")
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
