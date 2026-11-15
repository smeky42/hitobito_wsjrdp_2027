# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027
  # Family links (core FamilyMember): more kinds than the core's siblings, a
  # history, and a backport.
  #
  # Kinds: a link A->B says what B is for A (kind_label, the select of the
  # person form). Besides the core's sibling there are parent, child, spouse,
  # partner and relative (KINDS). Every link gets its inverse B->A (INVERSE:
  # parent and child swap, the others stay); only siblings are transitive --
  # a new sibling is linked with all siblings of the family, as in the core.
  # All members of a family share one family_key, whatever the kind.
  #
  # Own names: a link may name the relation itself (label,
  # e.g. "Aunt"); empty, a gendered word or the kind's label applies
  # (relation_label). The inverse gets its own name when the link is
  # made or later (inverse_label, e.g. "Niece").
  #
  # History: every link is versioned (PaperTrail) under the person it starts
  # from (main_id = person_id), so it shows in that person's log tab -- and,
  # through the inverse, in the other person's too. The texts are
  # version.association_change.family_member; to_s(:long), which the log uses
  # as the label, names the other person and the relation. people.family_key,
  # which the core sets with update_column, stays unversioned: it is a
  # technical key, the link versions tell the story.
  #
  # Backport of hitobito core commit 1adbba9ee ("Use safe_operator when
  # destroying family_members", core 2.5.8+): a missing inverse no longer
  # raises when a link is destroyed.
  module FamilyMember
    INVERSE = {
      "sibling" => "sibling",
      "parent" => "child",
      "child" => "parent",
      "spouse" => "spouse",
      "partner" => "partner",
      "relative" => "relative"
    }.freeze
    KINDS = INVERSE.keys.freeze

    def self.prepended(base)
      base.include WsjrdpSchemaValidationHelper
      base.has_paper_trail meta: {main_id: ->(link) { link.person_id }, main_type: ::Person.sti_name}
      base.normalizes :label, with: ->(value) { value.strip.presence }
      base.after_update :sync_inverse_kind, if: :saved_change_to_kind?
      base.after_update :sync_inverse_label
      base.after_destroy :clear_family_keys_without_links

      # additional_info is NOT NULL with {} as default, and validates_by_schema
      # (core) requires presence of every NOT NULL column -- which {} fails.
      # Nil stays refused by normalising it.
      base.remove_schema_validations :additional_info, only: :presence
      base.before_validation { self.additional_info ||= {} }

      # The core validates kind against its own list (i18n_enum :kind,
      # %w[sibling]); that validator gives way to one with KINDS. The labels
      # come from activerecord.attributes.family_member.kinds, where the wagon
      # adds the new kinds.
      base.remove_schema_validations :kind, only: :inclusion
      base.validates :kind, inclusion: {in: KINDS}, allow_blank: true
    end

    # The link the other way round (other -> person). The core's unique index
    # on (person_id, other_id) allows one link per direction, so it is that
    # one, whatever its kind or family_key.
    def inverse_link
      return nil unless person_id && other_id

      self.class.find_by(person_id: other_id, other_id: person_id)
    end

    # The inverse's own name: what the person is for the other. Given when a
    # link is made, or changed on an existing one (form field inverse_label);
    # read, it is the inverse link's label.
    def inverse_label
      @inverse_label_given ? @inverse_label : inverse_link&.label
    end

    def inverse_label=(value)
      @inverse_label_given = true
      @inverse_label = value
    end

    # A changed inverse label alone is no change of this record, so nested
    # attributes would skip saving it -- and with it the callback that carries
    # the label over.
    def changed_for_autosave?
      super || inverse_label_pending?
    end

    # What the other person is for this one: the own label; else, the
    # kind's gendered label; else the kind's label.
    def relation_label
      label.presence || gendered_kind_label || kind_label
    end

    # The log names a link by the other person and the relation; everything
    # else keeps the core's "A --(Geschwister)--> B".
    def to_s(format = nil)
      return "#{other} (#{relation_label})" if format == :long

      super()
    end

    private

    # The core raises FamilyKeyMismatch when the two people already belong to
    # different families (each its own family_key) -- in a form a 500. Here
    # it is an error on the link instead, and the person form shows it.
    def create_or_copy_family_key
      super
    rescue ::FamilyMember::FamilyKeyMismatch
      errors.add(:base, :family_key_mismatch,
        message: "#{person.short_full_name_with_nickname} und #{other.short_full_name_with_nickname} " \
                 "gehören schon zu verschiedenen Familien. Zwei bestehende Familien lassen sich nicht " \
                 "miteinander verknüpfen.")
      throw :abort
    end

    # The core keeps people.family_key when a person's last link goes; then it
    # is cleared, so that person starts a family of their own again.
    def clear_family_keys_without_links
      ids = [person_id, other_id].compact.reject do |id|
        self.class.where(person_id: id).or(self.class.where(other_id: id)).exists?
      end
      ::Person.where(id: ids).where.not(family_key: nil).update_all(family_key: nil) # rubocop:disable Rails/SkipsModelValidations
    end

    def gendered_kind_label
      gender = other&.gender
      return nil if gender.blank?

      I18n.t("activerecord.attributes.family_member.gendered_kinds.#{kind}.#{gender}", default: nil)
    end

    def inverse_kind = INVERSE.fetch(kind.to_s) { raise ::FamilyMember::NoRelationInversionDefined, self }

    def create_inverse_relation
      self.class.find_or_create_by!(person: other, kind: inverse_kind, other: person, family_key: family_key) do |inverse|
        inverse.label = @inverse_label
      end
      @inverse_label_given = false
    end

    def inverse_label_pending?
      return false unless @inverse_label_given && persisted?

      link = inverse_link
      link.present? && link.label != @inverse_label.to_s.strip.presence
    end

    # An inverse label given for an existing link goes to the inverse link.
    def sync_inverse_label
      return unless inverse_label_pending?

      @inverse_label_given = false
      inverse_link.update!(label: @inverse_label)
    end

    # A changed kind changes the inverse too (parent here, child there). The
    # inverse's own callback finds this link already matching, so it stops.
    # Siblings spread to the family only when a link is made, not on a change.
    def sync_inverse_kind
      inverse = inverse_link
      inverse.update!(kind: inverse_kind) if inverse && inverse.kind != inverse_kind
    end

    # Only siblings spread to the rest of the family (the core's own rule).
    def create_transitive_relations
      super if kind.to_s == "sibling"
    end

    # The core deletes the inverse with `delete`, skipping callbacks -- and so
    # its version -- and raises when it is missing; it also looks for it by
    # kind and family_key. `destroy` records it, and the inverse is found by
    # the swapped people alone (#inverse_link). It cannot loop: when the
    # inverse's own callback looks for this link, it is already gone.
    def destroy_inverse_relation
      inverse_link&.destroy
    end
  end
end
