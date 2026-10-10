# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027
  # A change of a person's primary role: a new role in a group with a fee
  # (the new primary group), the end of the chosen roles with a fee in the
  # current primary group, and what follows for the contract.
  #
  # Only the primary group counts (the fee follows its roles,
  # Person#build_payment_role). Roles without a fee there and roles in other
  # groups stay as they are. When the payment role type changes (UL to IST,
  # IST to CMT, ...), the new role needs a new contract: the contract in force
  # ends and status goes back to registered, so that the person prints and
  # signs again. A change within the same payment role type (IST to BMT,
  # Unit A to Unit B, an unapproved leader becoming a leader) keeps contract
  # and status. The dialog may decide otherwise either way (#contract); status
  # goes back only with the contract.
  #
  # A role with a fee the person already holds in the new primary group
  # becomes the primary role as it is: no new role is created.
  #
  # The dialog on the status page (Person::PrimaryRoleController) builds it
  # from its params step by step: target group (the current primary group
  # preselected), role type, the roles to end, the WSJ role; #save! carries
  # it out in one transaction.
  class PrimaryRoleChange
    include ActiveModel::Model
    include ActiveModel::Attributes

    # People in these states normally leave by the deregistration, not by a
    # role change: the dialog warns, but lets it happen.
    STATUSES_REFUSED = %w[deregistration_noted deregistered].freeze

    attribute :group_id, :integer
    attribute :role_type, :string
    attribute :end_role_ids, default: -> { [] }
    # The dialog's choice the other way round: the roles with a fee in the
    # primary group that stay (ticked); the others end.
    attribute :keep_role_ids, default: -> { [] }
    attribute :wsj_role, :string
    # Set by the dialog once it showed the roles to end, so that an empty
    # choice stays empty instead of falling back to the only role.
    attribute :end_roles_chosen, :boolean, default: false
    # The group the dialog's role choice was made for: a role chosen for
    # another group is stale once the group changes, and starts anew there.
    attribute :role_group_id, :integer
    # "keep" or "end": the dialog's choice for the contract; blank follows the
    # fee (#new_contract_by_default?).
    attribute :contract, :string

    CONTRACT_CHOICES = %w[keep end].freeze

    # ability: the user's (Ability), to offer only what the user may do --
    # groups and role types where the role may be created. Without one,
    # everything with a fee is offered (specs, scripts). The controller
    # authorizes the save itself.
    attr_reader :person, :by, :ability

    # The headings of the group choice, by group type.
    GROUP_HEADINGS = {
      "Group::Root" => "CMT",
      "Group::Ist" => "ISTs",
      "Group::Unit" => "Units",
      "Group::Extern" => "Externe"
    }.freeze

    # The short name of a payment role type (YP, UL, IST, CMT, EXT).
    WSJ_ROLE_BY_PAYMENT_ROLE_TYPE = {
      "Group::Unit::Member" => "YP",
      "Group::Unit::Leader" => "UL",
      "Group::Ist::Member" => "IST",
      "Group::Root::Member" => "CMT",
      "Group::Extern::Member" => "EXT"
    }.freeze

    validates :group_id, presence: {message: "wählen"}
    validates :role_type, presence: {message: "wählen"}
    validate :assert_target
    validate :assert_end_roles
    validate :assert_contract

    def initialize(person:, by:, ability: nil, **attrs)
      @person = person
      @by = by
      @ability = ability
      super(**attrs)
      self.group_id ||= person.primary_group_id
      self.role_type = nil if role_group_id.present? && role_group_id != group_id
      # No choice yet (nil): the default; emptied on purpose (""): stays empty.
      self.role_type = role_type.nil? ? default_role_type : role_type.presence
      self.end_role_ids = Array(end_role_ids).compact_blank.map(&:to_i)
      if end_role_ids.empty?
        fee_ids = primary_fee_roles.map(&:id)
        if end_roles_chosen
          self.end_role_ids = fee_ids - Array(keep_role_ids).compact_blank.map(&:to_i)
        elsif fee_ids.one?
          self.end_role_ids = fee_ids
        end
      end
    end

    def self.human_attribute_name(attr, options = {})
      {group_id: "Neue Hauptgruppe", role_type: "Rolle"}.fetch(attr.to_sym) { super }
    end

    # -- The person's roles today ---------------------------------------------

    def primary_group = person.primary_group

    def primary_roles = person.roles.select { |r| r.group_id == person.primary_group_id }.sort_by(&:id)

    # The roles with a fee in the primary group: the ones to choose from.
    def primary_fee_roles = primary_roles.select { |r| fee_role_type?(r.type) }

    # The roles without a fee in the primary group: they stay.
    def primary_other_roles = primary_roles.reject { |r| fee_role_type?(r.type) }

    # The roles in other groups: they stay.
    def other_group_roles = person.roles.reject { |r| r.group_id == person.primary_group_id }.sort_by(&:id)

    def end_roles = primary_fee_roles.select { |r| end_role_ids.include?(r.id) } - [existing_target_role]

    # The roles the current fee comes from: those in the primary group with
    # the current payment role type.
    def old_fee_roles
      primary_fee_roles.select { |r| ::Person::WSJRDP_ROLE_TYPE_TO_PAYMENT_ROLE_TYPE_MAP[r.type] == old_payment_role_type }
    end

    # -- The target -----------------------------------------------------------

    # Every group with a role type that carries a fee.
    def self.target_groups
      fee_group_types = ::Group.all_types.select { |type| type.role_types.any? { |rt| fee_role_type?(rt.sti_name) } }
      ::Group.where(type: fee_group_types.map(&:sti_name)).without_deleted.order(:lft)
    end

    def target_groups = self.class.target_groups

    # The groups to choose from under their headings (GROUP_HEADINGS), each
    # with its chips: the current primary group, a waiting list.
    def grouped_target_groups
      target_groups.select { |g| g.id == person.primary_group_id || selectable_role_types(g).any? }
        .group_by { |g| GROUP_HEADINGS[g.type] || "Weitere" }
        .sort_by { |heading, _| GROUP_HEADINGS.values.index(heading) || GROUP_HEADINGS.size }
        .map { |heading, groups| [heading, groups.map { |g| [g, group_chips(g)] }] }
    end

    def group_chips(group)
      chips = []
      chips << "bisher" if group.id == person.primary_group_id
      chips << "Warteliste" if group.name.to_s.match?(/warteliste/i)
      chips
    end

    # The role the person holds now: the roles with a fee in the primary
    # group, by name.
    def old_role_label
      names = primary_fee_roles.map { |r| r.class.model_name.human }
      names.any? ? names.join(", ") : "keine"
    end

    # Whether the target group offers a role with the person's current fee:
    # if not, any choice there changes the fee (and needs a new contract).
    def old_payment_role_type_offered?
      return true if old_payment_role_type.nil?

      target_role_types.any? { |rt| ::Person::WSJRDP_ROLE_TYPE_TO_PAYMENT_ROLE_TYPE_MAP[rt.sti_name] == old_payment_role_type }
    end

    # The short name of a role type's fee (YP, UL, IST, CMT, EXT).
    def payment_short(role_type) = WSJ_ROLE_BY_PAYMENT_ROLE_TYPE[::Person::WSJRDP_ROLE_TYPE_TO_PAYMENT_ROLE_TYPE_MAP[role_type]]

    def role_type_chips(role_type)
      chips = []
      chips << "bisher" if primary_fee_roles.any? { |r| r.type == role_type }
      chips << "vorhanden" if group && group.id != person.primary_group_id && target_group_roles.any? { |r| r.type == role_type }
      chips
    end

    # The person's roles in the target group.
    def target_group_roles = group ? person.roles.select { |r| r.group_id == group.id }.sort_by(&:id) : []

    # The role with a fee the person holds in the target group already, with
    # the chosen type: it becomes the primary role as it is (or, in the
    # primary group, stays it: #unchanged?).
    def existing_target_role
      return if group.nil?

      target_group_roles.find { |r| r.type == role_type }
    end

    # Primary group and role as they are: nothing to change.
    def unchanged? = !primary_group_changes? && existing_target_role.present?

    def primary_group_changes? = group.present? && group.id != person.primary_group_id

    def group
      return @group if defined?(@group) && @group&.id == group_id

      @group = group_id && ::Group.find_by(id: group_id)
    end

    # The role types with a fee the target group offers.
    def target_role_types
      return [] unless group

      group.class.role_types.select { |rt| fee_role_type?(rt.sti_name) }
    end

    def role_class = target_role_types.find { |rt| rt.sti_name == role_type }

    # The role types with a fee the user may choose in a group: those the
    # user may create there, and the one the person holds there already (it
    # becomes the primary role as it is).
    def selectable_role_types(target = group)
      return [] unless target

      held = person.roles.select { |r| r.group_id == target.id }.map(&:type)
      target.class.role_types.select do |rt|
        fee_role_type?(rt.sti_name) &&
          (ability.nil? || held.include?(rt.sti_name) || ability.can?(:create, rt.new(person: person, group: target)))
      end
    end

    # -- What follows ---------------------------------------------------------

    def old_payment_role_type = person.default_role_type_for_payment_role

    def new_payment_role_type = role_type && ::Person::WSJRDP_ROLE_TYPE_TO_PAYMENT_ROLE_TYPE_MAP[role_type]

    # The payment role changes: the role type the fee follows (UL to IST, ...),
    # not the payer kind (EarlyPayer/RegularPayer), which a role change keeps.
    def payment_role_changes? = new_payment_role_type.present? && new_payment_role_type != old_payment_role_type

    def new_payment_role = new_payment_role_type && "#{person.early_payer ? "EarlyPayer" : "RegularPayer"}::#{new_payment_role_type}"

    def old_regular_full_fee_eur = person.regular_full_fee_eur

    def new_regular_full_fee_eur = new_payment_role && WsjrdpInstallmentsHelper::PAYMENT_ROLE_TO_FULL_REGULAR_FEE_EUR[new_payment_role]

    # Without a choice the payment role type decides: another one needs a new
    # contract.
    def new_contract_by_default? = payment_role_changes?

    # Only a contract in force can be kept or ended; without one the choice
    # does not apply and the payment role type decides.
    def contract_in_force? = person.contract_status == "confirmed"

    def new_contract? = (contract_in_force? && contract.present?) ? contract == "end" : new_contract_by_default?

    def contract_choice_differs? = new_contract? != new_contract_by_default?

    # The contract stays though it was made for the old payment role type.
    def contract_kept_unfit? = payment_role_changes? && !new_contract?

    def old_payment_short = WSJ_ROLE_BY_PAYMENT_ROLE_TYPE.fetch(old_payment_role_type, old_payment_role_type)

    def new_payment_short = WSJ_ROLE_BY_PAYMENT_ROLE_TYPE.fetch(new_payment_role_type, new_payment_role_type)

    # The contract in force waits for its replacement (replacement_pending):
    # by law it holds until the new one is confirmed; nothing is collected
    # meanwhile.
    def contract_replaced? = new_contract? && person.contract_status == "confirmed"

    def status_to_registered? = new_contract? && person.status != "registered"

    # The WSJ role the new role suggests (UL, IST, CMT, ...).
    def suggested_wsj_role = role_type && ::Person::WSJRDP_ROLE_TYPE_TO_WSJ_ROLE_MAP[role_type]

    def wsj_role_options
      [["", "nicht gesetzt (folgt der Rolle)"]] + Settings.wsj_role.map { |key, label| [key.to_s, label] }
    end

    def wsj_role_changes? = new_wsj_role != person.wsj_role

    # The unit code of the new group for a YP or UL, as move_to_group.py in
    # wsjrdp_scripts sets it; nil when the group carries none (the person's
    # code stays).
    def new_unit_code
      return unless %w[Group::Unit::Member Group::Unit::Leader].include?(new_payment_role_type)

      group&.unit_code.presence
    end

    def unit_code_changes? = new_unit_code.present? && new_unit_code != person.unit_code

    # payment_role follows the roles by itself only while status is registered
    # (Person#payment_role_fluid?); otherwise it is set here, so that the fee
    # follows the new payment role type.
    def payment_role_set? = payment_role_changes? && person.payment_role != new_payment_role

    # The WSJ role ticked in the dialog: the one sent, else unset ("" -- it
    # follows the role) when the stored one is unset or only repeats the old
    # payment role, else the stored one, set on purpose. Few people need it
    # set at all.
    def chosen_wsj_role
      return wsj_role.to_s unless wsj_role.nil?

      wsj_role_fits_old_payment_role? ? "" : person.wsj_role.to_s
    end

    def wsj_role_fits_old_payment_role? = person.wsj_role.blank? || person.wsj_role == old_payment_short

    # A WSJ role set that differs from the new payment role: worth a look.
    def wsj_role_unfit? = new_wsj_role.present? && new_payment_role_type.present? && new_wsj_role != new_payment_short

    # Always chosen in the dialog; blank (nil) follows the role.
    def new_wsj_role = chosen_wsj_role.presence

    # What the dialog points out, each where it belongs (by topic) and all
    # together in the last step. Level :danger (the contract stays though it
    # no longer fits; saving stays possible), :warning (worth a look) or
    # :info.
    Notice = Struct.new(:level, :topic, :text)

    NOTICE_LEVELS = %i[danger warning info].freeze

    def notices # rubocop:disable Metrics/AbcSize
      list = status_notices
      list << Notice.new(:info, :roles, "Hauptgruppe und Rolle bleiben gleich. An Gruppen und Rollen ändert sich nichts.") if unchanged?
      if contract_kept_unfit?
        list << Notice.new(:danger, :contract, "Der Vertrag bleibt, passt aber nicht mehr: Er gilt für #{old_payment_short}, " \
          "die neue Beitragsrolle ist #{new_payment_short}.")
      elsif (contract_replaced? || status_to_registered?) && !payment_role_changes?
        list << Notice.new(:warning, :contract, "Neuer Vertrag, obwohl die Beitragsrolle gleich bleibt: drucken, " \
          "unterschreiben und hochladen. Bis zur Bestätigung gilt der bisherige Vertrag.")
      elsif contract_replaced? || status_to_registered?
        list << Notice.new(:info, :contract, "Neuer Vertrag nötig: drucken, unterschreiben und hochladen. Bis zur Bestätigung gilt der bisherige Vertrag.")
      end
      if wsj_role_unfit?
        list << Notice.new(:warning, :wsj_role, "Die WSJ-Rolle #{new_wsj_role} passt nicht zur neuen Beitragsrolle " \
          "#{new_payment_short}. Mit „nicht gesetzt“ folgt sie der Rolle.")
      end
      if payment_role_set?
        list << Notice.new(:info, :contract, "Bezahl-Rolle wird gesetzt: #{person.payment_role.presence || "keine"} → #{new_payment_role}.")
      end
      finance_hints.each { |text| list << Notice.new(:warning, :finance, text) }
      list.sort_by { |notice| NOTICE_LEVELS.index(notice.level) }
    end

    # Independent of the choice: shown from the start, above it.
    def status_notices
      return [] unless STATUSES_REFUSED.include?(person.status)

      [Notice.new(:warning, :status, "Im Status „#{Settings.status[person.status]}“ ist keine erneute Registrierung möglich.")]
    end

    # What may not fit the new fee any more.
    def finance_hints
      return [] unless payment_role_changes?

      hints = []
      hints << "Es gibt einen individuellen Ratenplan. Er passt womöglich nicht mehr zum neuen Beitrag." if person.wsjrdp_raw_installments_eur.present?
      hints << "Es gibt eine Beitragsreduktion. Sie passt womöglich nicht mehr zum neuen Beitrag." if person.active_total_fee_reduction.nonzero?
      hints << "Es gibt einen geplanten Ratenplan. Er passt womöglich nicht mehr zum neuen Beitrag." if person.planned_fee_rule.present?
      hints
    end

    # Complete enough to show what follows and to save.
    def complete? = group.present? && role_class.present?

    # -- Carrying it out ------------------------------------------------------

    # What follows is decided on the roles as they are now, before the new
    # role exists.
    def save!
      validate!
      decision = {contract_replaced: contract_replaced?, status_to_registered: status_to_registered?,
                  wsj_role: new_wsj_role, unit_code: (new_unit_code if unit_code_changes?),
                  payment_role: (new_payment_role if payment_role_set?), note: (note_text unless unchanged?)}
      ::Person.transaction do
        new_role = existing_target_role || role_class.create!(person: person, group: group, start_on: Time.zone.today)
        roles_to_end = end_roles
        # The new primary group first, logged; ending the old roles then does
        # not make core move it on its own (without a version).
        update_person!(**decision.except(:note))
        roles_to_end.each { |role| end_role!(role) }
        # A note only for a change of the primary role; the rest is in the
        # history of the person.
        ::Note.create!(subject: person, author: by, text: decision[:note]) if decision[:note]
        new_role
      end
    end

    # The note on the person (and the flash after saving): what happened in
    # short, not all of it (the history has that). Elements end with a
    # period, the last one without. A group change reads as in
    # move_to_group.py of wsjrdp_scripts, a role change after it.
    def note_text
      return "Hauptgruppe und Rolle unverändert" if unchanged?

      parts = []
      parts << group_change_text if primary_group_changes?
      parts << role_change_text if role_changes?
      parts << "Neuer Vertrag nötig: drucken, unterschreiben und hochladen. Bis zur Bestätigung gilt der bisherige Vertrag" if contract_replaced?
      parts.join(". ")
    end

    # The role type changes (the group may change too or not): the person
    # held no fee role of the chosen type in the primary group.
    def role_changes? = primary_fee_roles.none? { |r| r.type == role_type }

    def group_change_text
      "Am #{note_date} von #{primary_group&.display_name || "keiner Gruppe"} nach #{group.display_name} verschoben"
    end

    # With the date when it stands alone, without after the group change.
    def role_change_text
      old = primary_fee_roles.map { |r| r.class.model_name.human }.join(", ").presence || "keiner Rolle"
      text = "Rolle von #{old} zu #{role_class.model_name.human} gewechselt"
      primary_group_changes? ? text : "Am #{note_date} #{text}"
    end

    def note_date = Time.zone.today.strftime("%d.%m.%Y")

    def role_label(role_class, group) = "#{role_class.model_name.human} (#{group.display_name})"

    def self.fee_role_type?(type) = ::Person::WSJRDP_ROLE_TYPE_TO_PAYMENT_ROLE_TYPE_MAP.key?(type.to_s)

    private

    def fee_role_type?(type) = self.class.fee_role_type?(type)

    # The role type to start with in a target group other than the primary
    # one: the one the person holds there with a fee, else the current role
    # type when the group offers it (a group of the same kind, Unit A to
    # Unit B), else the only one there.
    def default_role_type
      return if group.nil? || group.id == person.primary_group_id

      fee_types = selectable_role_types.map(&:sti_name)
      current_types = primary_fee_roles.map(&:type)
      target_group_roles.map(&:type).find { |type| fee_types.include?(type) } ||
        current_types.find { |type| fee_types.include?(type) } ||
        (fee_types.one? ? fee_types.first : nil)
    end

    # Ended as of yesterday (core's soft destroy, kept in the history); a role
    # that starts today or later cannot end before it starts, so it is
    # removed, as core does with a young role.
    def end_role!(role)
      role.destroy!(always_soft_destroy: !(role.start_on && role.start_on >= Date.current))
    end

    def update_person!(contract_replaced:, status_to_registered:, wsj_role:, unit_code:, payment_role:) # rubocop:disable Metrics/ParameterLists
      person.reload
      person.primary_group_id = group.id
      person.wsj_role = wsj_role
      person.unit_code = unit_code if unit_code
      person.payment_role = payment_role if payment_role
      person.contract_status = "replacement_pending" if contract_replaced
      person.status = "registered" if status_to_registered
      person.save!(validate: false)
    end

    def assert_target
      return if group_id.blank? || role_type.blank?

      if group.nil?
        errors.add(:group_id, "gibt es nicht")
      elsif !target_groups.exists?(group.id)
        errors.add(:group_id, "hat keine Rolle mit Beitrag")
      elsif role_class.nil?
        errors.add(:role_type, "gibt es in dieser Gruppe nicht mit Beitrag")
      end
    end

    def assert_end_roles
      unknown = end_role_ids - primary_fee_roles.map(&:id)
      errors.add(:base, "Zu beendende Rollen müssen Beitragsrollen der Hauptgruppe sein.") if unknown.any?
    end

    def assert_contract
      errors.add(:base, "Unbekannte Auswahl beim Vertrag.") if contract.present? && CONTRACT_CHOICES.exclude?(contract)
    end
  end
end
