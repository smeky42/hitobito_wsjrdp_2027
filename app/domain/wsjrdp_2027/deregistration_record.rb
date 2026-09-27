# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027
  # What the Abmeldung page writes down beyond its dates and amounts, as one
  # sub-object of people.additional_info (KEY): which kind of deregistration it
  # is, and what the page's two documents carry -- whether the Abmelde-Formular
  # states the compensation of section 7.2 T&R, the text above the Moss
  # receipt's table, and whether that receipt prints its explanation paragraph.
  #
  # The store rule is that an absent value is the default: a missing kind reads
  # as a withdrawal, a missing flag as "shown", a missing text as no text. Only
  # what differs from a default is written, so KEY holds nothing of a person
  # nobody deregistered -- and vanishes entirely once everything is default
  # again.
  #
  # The person's deregistration_* accessors delegate here (Wsjrdp2027::Person):
  # each reader loads the record from the stored hash, each writer loads it,
  # sets its one attribute and stores it back. The hash is the truth, so
  # nothing here is memoised.
  class DeregistrationRecord
    include ActiveModel::Model
    include ActiveModel::Attributes

    KEY = "deregistration_record"
    # How the participation ended: the person withdrew from the contract
    # ("Abmeldung"), the contingent ended it ("Kündigung"), or the registration
    # was cancelled before a contract came about ("Storno der Registrierung").
    KINDS = %w[withdrawal termination cancellation].freeze
    DEFAULT_KIND = "withdrawal"
    # The two flags whose absent value means "shown".
    FLAGS = %w[
      form_show_contractual_compensation
      refund_receipt_show_default_explanation
    ].freeze
    # The record's attributes, in the order the edit form asks for them -- and
    # the order a change of the record is read in.
    ATTRS = %w[
      kind
      reply_due_date
      effective_reply_due_date
      form_created_date
      receipt_created_date
      receipt_created_by_id
      refund_account_holder
      refund_iban
      refund_bic
      refund_sepa_address
      person_role
      person_role_name
      person_team_unit
      receipt_snapshot
      form_show_contractual_compensation
      refund_receipt_text
      refund_receipt_show_default_explanation
    ].freeze
    # What a change of one value reads like: U+2192 between the two, an en dash
    # where there is no value. The Abmeldung page's flash and the person log
    # both say it this way.
    CHANGE_ARROW = "→"
    BLANK_VALUE = "–"

    attribute :kind, :string
    # The day the signed deregistration is to be back by -- and so the day up
    # to which the proposed Einbehalt stands.
    attribute :reply_due_date, :date
    # The deadline the made Abmelde-Formular names: reply_due_date, or two
    # weeks from the day it was made where none was entered -- fixed by
    # "PDF erzeugen", cleared by "Formular verwerfen".
    attribute :effective_reply_due_date, :date
    # The day the Abmelde-Formular was first made. It stays until the form is
    # discarded, so the form keeps its "Erstellt am" and a deadline counted
    # from it however often it is opened again.
    attribute :form_created_date, :date
    # The day the Moss refund receipt was first made and who made it, kept
    # until the receipt is discarded -- the receipt's "Erstellt am ... von ...".
    attribute :receipt_created_date, :date
    attribute :receipt_created_by_id, :integer
    # The receipt's figures as they stood when it was made
    # (Wsjrdp2027::RefundReceipt::FROZEN), a string-keyed hash -- a made
    # receipt keeps saying what it said.
    attribute :receipt_snapshot
    # The role, its name and the team or unit as the first made document
    # captured them (Wsjrdp2027::DeregistrationSnapshot::PERSON_KEYS).
    attribute :person_role, :string
    attribute :person_role_name, :string
    attribute :person_team_unit, :string
    # The account a refund goes to, as the first made document captured it
    # (Wsjrdp2027::DeregistrationSnapshot::REFUND_KEYS).
    attribute :refund_account_holder, :string
    attribute :refund_iban, :string
    attribute :refund_bic, :string
    attribute :refund_sepa_address, :string
    attribute :form_show_contractual_compensation, :boolean
    attribute :refund_receipt_text, :string
    attribute :refund_receipt_show_default_explanation, :boolean

    # Blank is the default, not an error: an absent kind reads as a withdrawal.
    validates :kind, inclusion: {in: KINDS}, allow_blank: true

    class << self
      # The record as it stands on the person. A key the record does not know
      # is none of its business and is left where it is.
      def load(person)
        stored = person.additional_info&.dig(KEY)
        stored = {} unless stored.is_a?(Hash)
        new(stored.stringify_keys.slice(*ATTRS))
      end

      # How one value of the record is worded, wherever it is read out: the
      # kind by its label, a flag as "anzeigen" or "ausblenden", the text as it
      # stands, and an en dash where there is nothing. The defaults are the
      # store's, so a missing value reads as what the page shows for it.
      def describe(sub_key, value)
        case sub_key.to_s
        when "kind" then I18n.t("people.deregistration_kinds.#{value.presence || DEFAULT_KIND}")
        when "reply_due_date", "effective_reply_due_date", "form_created_date", "receipt_created_date"
          value.present? ? I18n.l(value.to_date) : BLANK_VALUE
        when "receipt_snapshot"
          I18n.t("people.deregistration_record.#{value.present? ? "stored" : "not_stored"}")
        when "receipt_created_by_id" then value.present? ? (::Person.find_by(id: value)&.to_s || value.to_s) : BLANK_VALUE
        when *FLAGS then I18n.t("people.deregistration_form.#{shown?(value) ? "show" : "hide"}")
        else value.to_s.squish.presence || BLANK_VALUE
        end
      end

      # Whether two stored values of one attribute read the same: a stored
      # default and an absent value do, so nothing that shows them as a change
      # should.
      def same?(sub_key, from, to)
        describe(sub_key, from) == describe(sub_key, to)
      end

      # The one line a change of one value reads as, label included. ::Person is
      # the model -- a bare Person inside this module is Wsjrdp2027::Person.
      def describe_change(sub_key, from, to)
        "#{::Person.human_attribute_name(person_attr(sub_key))}: " \
          "#{describe(sub_key, from)} #{CHANGE_ARROW} #{describe(sub_key, to)}"
      end

      # What the person calls this attribute of the record.
      def person_attr(sub_key) = :"deregistration_#{sub_key}"

      # Which attribute of the record a person's accessor name stands for, nil
      # for a name that is not the record's.
      def sub_key(person_attr)
        name = person_attr.to_s.delete_prefix("deregistration_")
        name if ATTRS.include?(name)
      end

      # A flag as it is read: absent is what "shown" looks like in the store,
      # and a value some other path wrote as a string counts for what it says.
      def shown?(value)
        shown = ActiveModel::Type::Boolean.new.cast(value)
        shown.nil? || shown
      end
    end

    # What surrounds the text is none of it; whitespace alone is no text.
    def refund_receipt_text=(value)
      super(value&.to_s&.strip.presence)
    end

    def kind_or_default = kind.presence || DEFAULT_KIND

    def termination? = kind_or_default == "termination"

    def cancellation? = kind_or_default == "cancellation"

    def form_show_contractual_compensation?
      self.class.shown?(form_show_contractual_compensation)
    end

    def refund_receipt_show_default_explanation?
      self.class.shown?(refund_receipt_show_default_explanation)
    end

    # The sub-object as it is stored: string keys, and nothing at all for a
    # value that reads as the default -- the withdrawal, a flag that is on, an
    # empty text. A form that sends the defaults again therefore writes
    # nothing, and the store never says what an absent value already says.
    def to_h
      hash = {}
      hash["kind"] = kind if kind.present? && kind != DEFAULT_KIND
      hash["reply_due_date"] = reply_due_date.iso8601 if reply_due_date
      hash["effective_reply_due_date"] = effective_reply_due_date.iso8601 if effective_reply_due_date
      hash["form_created_date"] = form_created_date.iso8601 if form_created_date
      hash["receipt_created_date"] = receipt_created_date.iso8601 if receipt_created_date
      hash["receipt_created_by_id"] = receipt_created_by_id if receipt_created_by_id
      %w[refund_account_holder refund_iban refund_bic refund_sepa_address
        person_role person_role_name person_team_unit].each do |key|
        hash[key] = public_send(key) if public_send(key).present?
      end
      hash["receipt_snapshot"] = receipt_snapshot.to_h.stringify_keys if receipt_snapshot.present?
      hash["form_show_contractual_compensation"] = false if form_show_contractual_compensation == false
      hash["refund_receipt_text"] = refund_receipt_text if refund_receipt_text.present?
      hash["refund_receipt_show_default_explanation"] = false if refund_receipt_show_default_explanation == false
      hash
    end

    # Writes the record into the person's additional_info, under KEY -- a copy
    # of the column, so ActiveRecord sees the change. A record that is all
    # defaults leaves no key behind. Nothing is saved here.
    def store(person)
      info = (person.additional_info || {}).except(KEY)
      hash = to_h
      info[KEY] = hash if hash.present?
      person.additional_info = info
      self
    end
  end
end
