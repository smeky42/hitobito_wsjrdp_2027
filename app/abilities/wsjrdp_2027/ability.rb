# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Prepended to ::Ability: resolves the session's finance tier and hands the
# result to the UserContext the core builds inside its constructor
# (Wsjrdp2027::FinanceCap).
#
#   Ability.new(person)                                    # untouched
#   Ability.new(person, max_finance_permission: nil)       # the default tier
#   Ability.new(person, max_finance_permission: :finance)  # that tier
#
# Resolving HERE, before the context exists, is what keeps the context simple:
# the tier that ends up in the thread-local is the one in force, so the
# context only has to subtract what lies above it. Without the keyword the
# resolution is skipped entirely -- that is the line between a session and
# everything else (jobs, API requests, abilities for other people).
module Wsjrdp2027::Ability
  def initialize(user, max_finance_permission: Wsjrdp2027::FinanceCap::UNSET)
    tier = Wsjrdp2027::FinanceCap.resolve(user, max_finance_permission)
    Wsjrdp2027::FinanceCap.with(tier) { super(user) }
    define_document_abilities if user && !user.root?
    define_credential_abilities if user && !user.root?
    forbid_person_merges
  end

  # The core keys caches on this; an ability at another tier must not share
  # them with one of the same person at a different tier.
  def identifier
    tier = user_context&.finance_tier_in_force
    tier ? "#{super}-fin-#{tier}" : super
  end

  private

  # Nobody merges people -- root neither, whose `can :manage, :all` a rule of
  # the AbilityDsl could not take back. The core's merge (People::Merger)
  # deletes the source person and carries over neither the wagon's records
  # (bookings, payment notices, contracts) nor, in this core version, notes,
  # tags or siblings. Duplicates are told apart instead; ignoring one in the
  # core's list stays allowed.
  def forbid_person_merges
    cannot(:merge, PersonDuplicate)
  end

  # A document's own lists say who may read (:show), write (:create,
  # :update) and hide (:destroy) it (Wsjrdp2027::DocumentAccess); the
  # AbilityDsl has no rule that reads a record's lists. Root already may
  # everything. Anybody may ask for a list, which holds only what they may
  # read (DocumentResource). The Dokumentenverwaltung (:manage_documents) is
  # for admins.
  def define_document_abilities
    access = Wsjrdp2027::DocumentAccess.new(self)
    can(:index, WsjrdpDocument)
    can(:manage_documents, WsjrdpDocument) if access.admin?
    can(:show, WsjrdpDocument) { |document| access.allowed?(:read, document) }
    can([:create, :update], WsjrdpDocument) { |document| access.allowed?(:write, document) }
    can(:destroy, WsjrdpDocument) { |document| access.allowed?(:delete, document) }
  end

  # The credential store pages are for the document admins.
  # Root may do everything anyway.
  def define_credential_abilities
    can(:manage_credentials, WsjrdpCredential) if Wsjrdp2027::DocumentAccess.new(self).admin?
  end
end
