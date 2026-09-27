# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027
  # What the deregistration's documents say about the person as it stood when
  # the first of them was made. The account a refund goes to is kept in
  # deregistration_record's refund_* keys (REFUND_KEYS), the role, its name
  # and the team or unit in its person_* keys (PERSON_KEYS).
  # Both are captured by "PDF erzeugen" (the Abmelde-Formular, or the Moss
  # receipt where the form was not made) and read back by both documents and
  # the creditor section, so a later change of the person's data does not
  # change a document already made. Where nothing is captured, every value is
  # the person's current one.
  class DeregistrationSnapshot
    include ContractHelper

    # deregistration_record key => what the documents call it.
    PERSON_KEYS = {
      "person_role" => "role",
      "person_role_name" => "role_name",
      "person_team_unit" => "team_unit"
    }.freeze
    # deregistration_record key => people column.
    REFUND_KEYS = {
      "refund_account_holder" => :sepa_name,
      "refund_iban" => :sepa_iban,
      "refund_bic" => :sepa_bic,
      "refund_sepa_address" => :sepa_address
    }.freeze

    # The bank data in the shape Wsjrdp2027::SepaAccount reads.
    Sepa = Struct.new(:sepa_name, :sepa_iban, :sepa_bic, :sepa_address, keyword_init: true)

    attr_reader :person

    def self.for(person) = new(person)

    def initialize(person)
      @person = person
    end

    # The captured role, its name and the team or unit; nil where none is.
    def stored
      values = PERSON_KEYS.to_h { |key, name| [name, person.public_send(:"deregistration_#{key}")] }
      values.values.any?(&:present?) ? values : nil
    end

    # Whether anything is captured -- the account or the rest.
    def stored? = stored.present? || refund_stored?

    # Whether the account a refund goes to is captured.
    def refund_stored?
      REFUND_KEYS.keys.any? { |key| person.public_send(:"deregistration_#{key}").present? }
    end

    # The role, its name and the team or unit as they stand now -- read once
    # per object.
    def capture
      @capture ||= {
        "role" => person.wsjrdp_role.to_s,
        "role_name" => person_payment_role_full_name(person).to_s,
        "team_unit" => person.team_unit_code.to_s
      }
    end

    # Stores the current values unless some are stored already; the caller
    # saves the person.
    def capture!
      return self if stored?

      REFUND_KEYS.each do |key, column|
        person.public_send(:"deregistration_#{key}=", person.public_send(column).to_s.presence)
      end
      PERSON_KEYS.each { |key, name| person.public_send(:"deregistration_#{key}=", capture[name].presence) }
      self
    end

    def value(key) = (stored || capture)[key.to_s].to_s

    # The account a refund goes to: the captured one, or the person's current.
    def sepa
      values = REFUND_KEYS.to_h do |key, column|
        [column, refund_stored? ? person.public_send(:"deregistration_#{key}").to_s : person.public_send(column).to_s]
      end
      Sepa.new(**values)
    end

    def role = value("role")

    def role_name = value("role_name")

    def team_unit = value("team_unit")

    # Forgets everything captured; the caller saves the person.
    def clear!
      REFUND_KEYS.each_key { |key| person.public_send(:"deregistration_#{key}=", nil) }
      PERSON_KEYS.each_key { |key| person.public_send(:"deregistration_#{key}=", nil) }
      self
    end
  end
end
