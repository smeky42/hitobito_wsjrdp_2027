# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# "Dokument-Arten", a tab of the main section Dokumente
# (/document_management/document_kinds), for admins: the kinds of document
# (WsjrdpDocumentKind) as an expandable table. A row opens into the kind's
# form (show, lazily), which is also the kind's own page; new creates one,
# destroy deletes one no document has.
#
# The form (document_management/document_kinds/_form) gives the lists as
# tag selects and the role rules as one card per rule, in the order of the
# cards: the params keep the order of the form. Keys of a kind that documents
# have are fixed; additional_info is shown, not changed. A save goes back to
# where the form was (return_to: the list with its state, or the kind's page);
# a failed one shows the kind's page with the errors.
class DocumentManagement::DocumentKindsController < ApplicationController
  include Wsjrdp::TableStateful

  LIST_PARAMS = %i[readable_by writable_by deletable_by].freeze
  FILE_PARAMS = %i[content_types extensions].freeze
  KEY_PARAMS = %i[subject_type key secondary_key].freeze

  POLICY = wsjrdp_expandable_table_policy prefix: "",
    columns: DocumentManagement::DocumentKindsColumns::COLUMNS,
    sort: {hidden: [["position", "asc"], ["label", "asc"]]},
    cols: {default: DocumentManagement::DocumentKindsColumns::COLUMNS.default_keys},
    per_page: {default: 100}

  before_action { authorize!(:manage_documents, WsjrdpDocument) }
  before_action :find_kind, only: [:show, :update, :destroy]

  helper_method :kind, :kinds, :document_counts, :used?, :return_to, :person_tags

  def index
  end

  # The kind's form: its page, or the lazy detail of its row.
  def show
    render layout: false if turbo_frame_request?
  end

  def new
    @kind = WsjrdpDocumentKind.new(subject_type: "Person",
      position: (WsjrdpDocumentKind.maximum(:position) || 0) + 10)
  end

  def create
    @kind = WsjrdpDocumentKind.new
    save_or_render(:new, t(".created", label: params.dig(:kind, :label)))
  end

  def update
    save_or_render(:show, t(".updated", label: kind.label))
  end

  def destroy
    if used?(kind)
      redirect_to document_management_document_kinds_path, alert: t(".used")
    else
      kind.destroy!
      redirect_to document_management_document_kinds_path, notice: t(".destroyed", label: kind.label)
    end
  end

  private

  attr_reader :kind

  def find_kind
    @kind = WsjrdpDocumentKind.find(params[:id])
  end

  def table_state = wsjrdp_expandable_table_state(POLICY)

  def kinds
    @kinds ||= Wsjrdp::ExpandableTableRows.new(table_state, WsjrdpDocumentKind.all,
      sort: DocumentManagement::DocumentKindsColumns::COLUMNS.sort_expressions)
  end

  # Where a save goes back to: the list the form was opened in (the
  # referrer of the row's frame, with the table's state), else the kind's
  # page; only paths of this tab.
  def return_to
    @return_to ||= begin
      given = params[:return_to].presence || (request.referer if turbo_frame_request?)
      uri = given && URI.parse(given.to_s)
      path = uri && [uri.path, uri.query].compact_blank.join("?")
      path if path&.start_with?(document_management_document_kinds_path)
    rescue URI::InvalidURIError
      nil
    end
  end

  def save_or_render(template, notice)
    kind.assign_attributes(kind_attributes)
    if kind.save
      redirect_to return_to || document_management_document_kind_path(kind), notice: notice
    else
      render template, status: 422
    end
  end

  def kind_params = params.require(:kind)

  def kind_attributes
    attributes = kind_params.permit(:label, :description, :position, :max_upload_size_mb, :people_column_name).to_h
    attributes.merge!(kind_params.permit(*KEY_PARAMS).to_h) unless kind.persisted? && used?(kind)
    attributes[:max_upload_size_mb] = attributes[:max_upload_size_mb].presence
    LIST_PARAMS.each { |list| attributes[list] = entries(kind_params[list]) }
    FILE_PARAMS.each { |list| attributes[list] = entries(kind_params[list]).map(&:downcase).presence }
    attributes[:role_rules] = rules(kind_params[:rules])
    attributes
  end

  # A tag select's values (an Array) or a text (entries separated by commas
  # or spaces), as a list without blanks.
  def entries(value) = Array(value).flat_map { |part| part.to_s.split(/[\s,]+/) }.compact_blank

  # The rule cards of the form ({index => fields}, in the order of the cards)
  # as role_rules; a card without anything chosen adds no rule.
  def rules(cards)
    return [] if cards.blank?

    cards = cards.respond_to?(:to_unsafe_h) ? cards.to_unsafe_h : cards.to_h
    cards.values.filter_map { |card| rule(card) }
  end

  def rule(card)
    rule = {"roles" => entries(card["roles"]), "offer_to" => entries(card["offer_to"]),
            "not_for_status" => entries(card["not_for_status"])}.compact_blank
    rule["required"] = true if card["required"] == "1"
    tag = card["missing_tag"].to_s.strip
    rule["missing_tag"] = missing_tag(tag, card) if tag.present?
    rule.presence
  end

  def missing_tag(tag, card)
    {"tag" => tag, "from_status" => entries(card["missing_tag_from_status"]).presence,
     "remove_on_upload" => (true if card["remove_on_upload"] == "1")}.compact
  end

  # The tags people carry, for the suggestions of a rule's missing tag.
  def person_tags
    @person_tags ||= ActsAsTaggableOn::Tag.joins(:taggings).where(taggings: {taggable_type: "Person"})
      .distinct.order(:name).pluck(:name)
  end

  # The documents per kind (subject type and keys).
  def document_counts
    @document_counts ||= WsjrdpDocument.group(:subject_type, :key, :secondary_key).count
  end

  def used?(record)
    document_counts[[record.subject_type_was || record.subject_type, record.key_was || record.key,
      record.secondary_key_was || record.secondary_key]].to_i.positive?
  end
end
