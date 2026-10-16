# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The documents grouped by person and kind (the tab Nach Person und Art of
# the main section Dokumente, DocumentManagement::DocumentGroupsController):
# one Group per subject, key and secondary key -- a person's documents of one
# kind, whatever their numbers; derivations (a preview of a document) are
# left out. A combination is one key number and secondary key number of the
# group; each has at most one current document, so a group has a current
# document in all, some or none of its combinations (#current_state). Only
# the documents of the given relation count, so a filter on the documents
# (DocumentManagement::DocumentsFilterSchema) narrows each group rather than
# hiding it.
#
# A group's URL parameter (Group#to_param, .slot_from_param) is the subject
# and the keys as a file name writes them, without numbers:
#
#   <subject_type>-<subject_id>-<key>[--<secondary_key>]
#
# e.g. "person-42-deregistration--signed_form"; the type as
# Wsjrdp2027::DocumentSubjects names it in a URL, "nil" for an empty type or
# id. Keys hold no "-" and start with a letter, so the parameter is unique and
# reads back; only the canonical form is accepted.
module DocumentManagement::DocumentGroups
  SLOT = %i[subject_type subject_id key secondary_key].freeze

  COUNTS = {
    count: "COUNT(*)",
    combinations: "COUNT(DISTINCT (wsjrdp_documents.key_number, wsjrdp_documents.secondary_key_number))",
    current: "COUNT(*) FILTER (WHERE wsjrdp_documents.status = '#{WsjrdpDocument::CURRENT}')",
    superseded: "COUNT(*) FILTER (WHERE wsjrdp_documents.status = '#{WsjrdpDocument::SUPERSEDED}')",
    deleted: "COUNT(*) FILTER (WHERE wsjrdp_documents.status = '#{WsjrdpDocument::DELETED}')",
    missing: "COUNT(*) FILTER (WHERE wsjrdp_documents.file_status = '#{WsjrdpDocument::FILE_MISSING}')",
    first_at: "MIN(wsjrdp_documents.created_at)",
    last_at: "MAX(wsjrdp_documents.created_at)",
    bytes: "COALESCE(SUM(wsjrdp_documents.byte_size), 0)"
  }.freeze

  NIL_TOKEN = "nil"
  PARAM_FORMAT = /\A(?<type>[a-z][a-z0-9_]*)-(?<id>#{NIL_TOKEN}|\d+)-(?<keys>[a-z].*)\z/

  # One group; `kind` is its WsjrdpDocumentKind, nil when there is none;
  # `subject` the Person it is for, nil for any other subject or a person
  # that is gone.
  Group = Struct.new(*SLOT, *COUNTS.keys, :kind, :subject, keyword_init: true) do
    # The URL parameter (see above); nil for a group whose type or keys a
    # parameter cannot hold (a type that is no kind, a key of an older form).
    def to_param = DocumentManagement::DocumentGroups.param_for(to_h.slice(*SLOT))

    # The row key: the parameter, or for a group without one its values
    # digested.
    def row_key = to_param || "g#{Digest::SHA256.hexdigest(to_h.slice(*SLOT).to_json)[0, 16]}"

    # The group's own documents, by their numbers, each combination newest
    # first.
    def versions
      WsjrdpDocument.where(to_h.slice(*SLOT)).where(derived_from_id: nil)
        .order(:key_number, :secondary_key_number, created_at: :desc, id: :desc)
    end

    # :all, :some or :none of the combinations have a current document.
    def current_state
      if current.zero? then :none
      elsif current >= combinations then :all
      else
        :some
      end
    end

    def label = kind&.label

    # The order of groups a sort leaves equal: by person (name, then id),
    # then by the position of the kind (groups without a kind last), then by
    # keys.
    def tiebreak_key
      [subject&.to_s&.downcase || "\u{10FFFF}", subject_id.to_i, kind&.position || Float::INFINITY,
        key.to_s, secondary_key.to_s]
    end
  end

  # The parameter of a slot ({subject_type:, subject_id:, key:,
  # secondary_key:}), nil when it cannot hold it.
  def self.param_for(slot)
    type = slot[:subject_type].nil? ? NIL_TOKEN : Wsjrdp2027::DocumentSubjects.param_for(slot[:subject_type])
    filename = Wsjrdp2027::DocumentFilename
    secondary = slot[:secondary_key].to_s
    return nil unless type && filename.valid_key?(slot[:key])
    return nil unless secondary == "" || filename.valid_key?(secondary)

    param = "#{type}-#{slot[:subject_id].nil? ? NIL_TOKEN : Integer(slot[:subject_id])}-#{slot[:key]}"
    (secondary == "") ? param : "#{param}--#{secondary}"
  end

  # The slot a parameter names, nil for one that is not the canonical
  # parameter of a slot.
  def self.slot_from_param(param)
    match = PARAM_FORMAT.match(param.to_s)
    return nil unless match

    type = (match[:type] == NIL_TOKEN) ? nil : Wsjrdp2027::DocumentSubjects.type_for_param(match[:type])
    return nil if type.nil? && match[:type] != NIL_TOKEN

    key, secondary_key, rest = match[:keys].split("--", 3)
    return nil if rest

    slot = {subject_type: type, subject_id: (match[:id] == NIL_TOKEN) ? nil : match[:id].to_i, key: key,
            secondary_key: secondary_key.to_s}
    (param_for(slot) == param) ? slot : nil
  end

  # The group of a slot over all its documents, nil when it has none.
  def self.find(slot) = groups(WsjrdpDocument.where(slot)).first

  # The groups of the documents of `relation`, ordered by subject and keys.
  def self.groups(relation)
    kinds = WsjrdpDocumentKind.all.index_by { |kind| [kind.subject_type, kind.key, kind.secondary_key] }
    columns = SLOT.map { |name| "wsjrdp_documents.#{name}" }
    groups = relation.where(derived_from_id: nil).reorder(nil).group(*columns).order(*columns)
      .pluck(*columns.map { |column| Arel.sql(column) }, *COUNTS.values.map { |sql| Arel.sql(sql) })
      .map { |values| Group.new(**(SLOT + COUNTS.keys).zip(values).to_h) }
    people = Person.where(id: groups.select { |group| group.subject_type == "Person" }.map(&:subject_id).uniq)
      .index_by(&:id)
    groups.each do |group|
      # An aggregate comes back as a plain UTC time, not in the app's zone.
      group.first_at = group.first_at&.in_time_zone
      group.last_at = group.last_at&.in_time_zone
      group.kind = kinds[[group.subject_type, group.key, group.secondary_key]]
      group.subject = people[group.subject_id] if group.subject_type == "Person"
    end
  end
end
