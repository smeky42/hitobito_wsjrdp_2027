# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Generic two-column "Label | Wert" rows for detail sections -- the form-like
# grid of the tx/ae detail pages (WsjrdpFormHelper#form_like_labeled), but
# hand-buildable row by row, with widgets/forms in the value column and an
# optional muted help line. The wsjrdp_ prefix keeps these clear of core
# hitobito helpers (same convention as wsjrdp_format_attr & co).
#
#   = wsjrdp_labeled_row("Person") do
#     = wsjrdp_row_form(booking_path(booking), method: :patch) do
#       ... input + button ...
#     = wsjrdp_row_help do
#       Bisher:
#       = assoc_link_with_newtab(booking.person)
module WsjrdpLabeledRowsHelper
  # One grid row: label right-aligned in column 1 (same responsive cols as
  # form_like_labeled), value/widgets in column 2 -- a <div>, so forms and
  # flex lines can be nested safely.
  def wsjrdp_labeled_row(label, &block)
    value = capture(&block)
    label_col = content_tag(:div, label, class: "col-md-3 col-xl-2 text-md-end text-muted")
    value_col = content_tag(:div, value, class: "labeled pb-1 col-md-9 col-lg-8 col-xl-8 mw-63ch")
    row = content_tag(:div, safe_join([label_col, value_col]), class: "row mb-2")
    safe_join([wsjrdp_labeled_row_styles, row])
  end

  # A horizontal line of widgets inside a row (link + chip + buttons, ...).
  def wsjrdp_row_line(&block)
    content_tag(:div, capture(&block), class: "d-flex flex-wrap align-items-center gap-2")
  end

  # An inline action form laid out like wsjrdp_row_line. Turbo is off -- these
  # detail sections use plain full-page posts with delegated JS confirms.
  def wsjrdp_row_form(url, css: nil, method: :post, &block)
    form_tag(url, method: method, data: {turbo: false},
      class: ["d-flex flex-wrap align-items-center gap-2", css].compact.join(" "), &block)
  end

  # Muted help line under a row's widgets, on its own line -- same styling as
  # hitobito's inline field help ("form-text", see e.g. the ae detail page).
  def wsjrdp_row_help(content = nil, &block)
    content = capture(&block) if block
    content_tag(:span, content, class: "form-text d-block")
  end

  # Small companion link opening url in a new tab (arrow icon next to the
  # regular same-tab link).
  def wsjrdp_newtab_link(url)
    link_to(url, target: "_blank", rel: "noopener", class: "ms-1 text-muted",
      title: "In neuem Tab öffnen", "aria-label": "In neuem Tab öffnen") do
      icon(:"external-link-alt")
    end
  end

  # Like hitobito's assoc_link (FormatHelper): renders a link to the record
  # only when a route exists AND can?(:show, record) -- plus the new-tab
  # companion icon. Without permission only the plain (escaped) text is shown,
  # no link and no icon (mirroring link_to_if).
  #
  #   assoc_link_with_newtab(person)                       # text: person.to_s
  #   assoc_link_with_newtab(entry, "##{entry.id}")        # custom text
  #   assoc_link_with_newtab(entry, "##{entry.id}", class: "fw-semibold")
  def assoc_link_with_newtab(val, label = nil, **html_options)
    label ||= val.to_s
    return ERB::Util.html_escape(label) unless assoc_link?(val)

    safe_join([link_to(label, val, html_options), wsjrdp_newtab_link(url_for(val))])
  end

  private

  # The little real CSS the rows need (entity-autocomplete sizing), emitted
  # once per response on first row use (project convention: view-local styles
  # with an ivar once-guard).
  def wsjrdp_labeled_row_styles
    return "".html_safe if @wsjrdp_labeled_row_styles_emitted
    @wsjrdp_labeled_row_styles_emitted = true
    content_tag(:style, ".wsjrdp-lr-entity { max-width: 24rem; flex: 1 1 14rem; }".html_safe)
  end
end
