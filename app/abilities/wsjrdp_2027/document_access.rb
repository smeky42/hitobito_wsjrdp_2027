# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027
  # Who may read, write and delete (hide) a document: its lists readable_by,
  # writable_by and deletable_by name entries, and one entry the viewer
  # meets suffices (doc/wsjrdp/documents.md):
  #
  #   person          the viewer is the subject           (subject a person)
  #   log             the viewer may :log the subject     (subject a person)
  #   update          the viewer may :update the subject  (subject a person)
  #   finance_audit   the viewer's finance tier is at least that one
  #   finance         likewise                            (any subject)
  #   finance_manage  likewise
  #
  # An entry that means nothing for the subject's kind
  # (Wsjrdp2027::DocumentSubjects), and one nobody knows, gives nobody access.
  # Admins may everything. A document that is not current (superseded or
  # deleted) is read by who meets readable_by and may :log its subject, and
  # changed only by admins.
  #
  # Wsjrdp2027::Ability asks this with itself as the ability, so the finance
  # tier is the one in force in the session (Wsjrdp2027::FinanceCap).
  class DocumentAccess
    LISTS = {read: :readable_by, write: :writable_by, delete: :deletable_by}.freeze
    FINANCE_ENTRIES = Wsjrdp2027::FinanceAccess::FINANCE_TIERS.map(&:to_s).freeze
    SUBJECT_ENTRIES = {"log" => :log, "update" => :update}.freeze

    attr_reader :ability

    def initialize(ability)
      @ability = ability
    end

    # Whether the ability's user may read, write or delete the document; for
    # a new document :write is whether it may be made. An older version
    # (superseded or deleted) is only read, and only by who meets its list
    # AND may :log its subject; without a subject only admins read it.
    def allowed?(action, document)
      return true if admin?
      return false unless Wsjrdp2027::DocumentSubjects.known?(document.subject_type)

      listed = Array(document.public_send(LISTS.fetch(action))).any? do |entry|
        meets_entry?(entry, document.subject_type, document.subject)
      end
      return listed if document.status == WsjrdpDocument::CURRENT

      action == :read && listed && document.subject.present? && ability.can?(:log, document.subject)
    end

    # Whether the ability's user meets one access entry for a subject of the
    # kind (Wsjrdp2027::DocumentSubjects); also what decides who is offered a
    # document kind (WsjrdpDocumentKind#offered?).
    def meets_entry?(entry, subject_type, subject)
      entry = entry.to_s
      return finance_at_least?(entry) if FINANCE_ENTRIES.include?(entry)
      return false unless Wsjrdp2027::DocumentSubjects.known?(subject_type)
      return false unless Wsjrdp2027::DocumentSubjects.fetch(subject_type).entries.include?(entry)
      return false if subject.nil?
      return subject == ability.user if entry == "person"

      action = SUBJECT_ENTRIES[entry]
      action.present? && ability.can?(action, subject)
    end

    def admin?
      permissions.include?(:admin)
    end

    private

    def finance_at_least?(entry)
      tiers = Wsjrdp2027::FinanceCap::TIERS
      tiers.index(Wsjrdp2027::FinanceCap.highest(permissions)) >= tiers.index(entry.to_sym)
    end

    def permissions
      ability.user_context&.all_permissions || []
    end
  end
end
