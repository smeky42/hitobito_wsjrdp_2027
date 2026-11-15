# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027
  # Who the e-mail with a person's Abmelde-Formular comes from and goes to --
  # the rules the scripts' mailings follow (wsjrdp2027._people:
  # _row_to_mailing_to, row_to_mailing_cc), held here so the form and its mail
  # name the same people.
  #
  # - To: the person's e-mail, for CMT and UL also the contingent address
  #   (wsjrdp_email).
  # - Cc: the additional e-mails marked for mailings, and for a youth
  #   participant or anybody under 18 the guardians' e-mails (only the first
  #   where one guardian signs alone) -- minus what To has, sorted.
  # - From: the helpdesk of the person's role (HELPDESK_EMAILS).
  # - Bcc of a youth participant or unit leader: the Support-CMT addresses
  #   (groups.additional_info["support_cmt_mail_addresses"]) of the person's
  #   unit. A unit is a group with a unit_code -- the registration groups and
  #   the waiting lists are of type Group::Unit too, but have none. A person
  #   outside every unit (on a waiting list, say) gets the unit of the most
  #   recent role in one, ended roles included; a person never in a unit the
  #   primary group's addresses.
  # - Bcc of every role: the helpdesk as well, where a ticket is entered, so
  #   the mail lands in the ticket.
  #
  # The role is the one the form names (DeregistrationSnapshot), so the mail
  # and the form it carries agree.
  class DeregistrationMailRecipients
    HELPDESK_EMAILS = {
      "YP" => "unit-management@worldscoutjamboree.de",
      "UL" => "unit-management@worldscoutjamboree.de",
      "IST" => "ist@worldscoutjamboree.de",
      "BMT" => "ist@worldscoutjamboree.de"
    }.freeze
    DEFAULT_HELPDESK_EMAIL = "info@worldscoutjamboree.de"
    # The roles whose Bcc comes from the unit.
    UNIT_ROLES = %w[YP UL].freeze
    # The roles whose mail goes to the contingent address as well.
    WSJRDP_EMAIL_ROLES = %w[CMT UL].freeze
    # Where the unit the Bcc comes from was found: the primary group is a
    # unit, the most recent role in a unit, or no unit at all.
    UNIT_SOURCES = %w[unit last_unit primary_group].freeze

    attr_reader :person

    def initialize(person, role: nil)
      @person = person
      @role = role
    end

    def role = @role ||= DeregistrationSnapshot.for(person).role

    def from = HELPDESK_EMAILS.fetch(role, DEFAULT_HELPDESK_EMAIL)

    def unit_roles? = UNIT_ROLES.include?(role)

    # The group the Bcc is read from, nil for a role that takes none.
    def unit_group
      return nil unless unit_roles?

      unit_lookup.first
    end

    def unit_source
      return nil unless unit_roles?

      unit_lookup.last
    end

    # The unit's addresses, then the helpdesk where a ticket is entered; each
    # once, in that order.
    def bcc
      addresses = unit_group ? Array(unit_group.support_cmt_mail_addresses) : []
      addresses += [from] if person.deregistration_issue.present?
      clean(addresses)
    end

    def to
      addresses = [person.email]
      addresses << person.wsjrdp_email if WSJRDP_EMAIL_ROLES.include?(role)
      clean(addresses)
    end

    def cc
      addresses = person.additional_emails.select(&:mailings).map(&:email) + guardian_emails
      (clean(addresses) - to).sort
    end

    # The guardians sign for a youth participant and for anybody under 18
    # (DeregistrationForm#guardian_names), so they get the mail too.
    def guardian_emails
      form = DeregistrationForm.new(person)
      return [] unless person.yp? || form.minor?

      if person.additional_contact_single
        [person.additional_contact_email_a]
      else
        [person.additional_contact_email_a, person.additional_contact_email_b]
      end
    end

    def as_json(*)
      group = unit_group
      {
        "from" => from,
        "to" => to,
        "cc" => cc,
        "bcc" => bcc,
        "unit" => group && {"group_id" => group.id, "name" => group_name(group), "source" => unit_source}
      }
    end

    def group_name(group) = group.short_name.presence || group.name

    private

    # Each address once, trimmed, in the order given; blanks dropped.
    def clean(addresses) = addresses.map { |address| address.to_s.strip }.compact_blank.uniq

    # [group, source], looked up once.
    def unit_lookup
      @unit_lookup ||= begin
        primary = person.primary_group
        if unit?(primary)
          [primary, "unit"]
        elsif (last = last_unit)
          [last, "last_unit"]
        else
          [primary, "primary_group"]
        end
      end
    end

    def unit?(group) = group.present? && group.additional_info.to_h["unit_code"].present?

    # The group of the most recent role in a unit, ended roles included -- the
    # order Person#team_unit_code reads the roles in.
    def last_unit
      group_id = person.roles_unscoped
        .joins(:group)
        .where("groups.additional_info ->> 'unit_code' <> ''")
        .order(Arel.sql("roles.start_on DESC NULLS LAST, roles.created_at DESC"))
        .pick("groups.id")
      group_id && ::Group.find_by(id: group_id)
    end
  end
end
