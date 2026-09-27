# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027
  # The slip the finance team pays a deregistration back from: everything the
  # transfer needs, on one page, in the wording Moss and the bank expect.
  #
  # Two fields have a hard length and are built to it:
  #
  # - the booking text Moss shows, 60 characters, UTF-8 as typed;
  # - the remittance information of the transfer, 140 characters by SEPA --
  #   but Moss appends its own " <36-char uuid>" to it, so 103 are ours.
  #
  # Both are "prefix, name, ticket": the role, the registration id and the
  # ticket are what the booking is found by later and never give way, so the
  # name takes whatever room is left (Person#name_within) and is dropped
  # entirely when there is none. The remittance information is measured after
  # transliteration (Wsjrdp2027::SepaText), because that is the string that is
  # actually sent -- "Müller" leaves the house as "Mueller".
  #
  # Above the table stand the optional text the Abmeldung page carries and the
  # explanation paragraph the template composes from the figures below; under
  # it, who asked for the receipt and when.
  #
  # See doc/typst_documents.md.
  class RefundReceipt
    include ContractHelper

    BOOKING_TEXT_MAX = 60
    # 140 characters of SEPA remittance information, minus the 37 Moss adds
    # afterwards: a space and a 36-character uuid.
    PURPOSE_MAX = 140 - 37
    TEMPLATE = "refund_receipt.typ"
    # The figures a made receipt keeps saying, whatever is booked or changed
    # afterwards: they are stored by "PDF erzeugen" and read back from then on.
    FROZEN = %w[
      creditor_name total_fee_contract_text total_fee_text total_fee_label
      amount_paid_text compensation_text amount_cents amount_text
      booking_text purpose
    ].freeze

    attr_reader :person, :generated_by

    def initialize(person, generated_by: nil)
      @person = person
      @generated_by = generated_by
    end

    def title = "Überweisung einer Rückzahlung an #{role} #{person.id} #{person.short_full_name}"

    # Optional: what stands above the explanation paragraph, or nothing at all.
    def greeting = person.deregistration_refund_receipt_text.to_s

    def show_explanation? = person.deregistration_refund_receipt_show_default_explanation?

    # Whether the receipt is made -- it is, from "PDF erzeugen" on, until it
    # is discarded.
    def created? = person.deregistration_receipt_created_date.present?

    # The day the receipt counts as made: the stored one, or today for a
    # receipt not made yet.
    def created_on = person.deregistration_receipt_created_date || Date.current

    # Who made the receipt: the stored person, or whoever asks for one not
    # made yet.
    def creator
      id = person.deregistration_receipt_created_by_id
      id ? ::Person.find_by(id: id) : generated_by
    end

    # Stores today and the person making it where nothing is stored yet --
    # with the person's data (captured now unless the Abmelde-Formular already
    # did) and the receipt's figures as they stand now -- and saves the person.
    # Answers whether anything was written.
    def record_creation!(by)
      return false if created?

      snapshot.capture!
      figures = FROZEN.index_with { |key| public_send(key).to_s }
      person.deregistration_receipt_snapshot = figures
      person.deregistration_receipt_created_date = Date.current
      person.deregistration_receipt_created_by_id = by&.id
      person.save!
      @snapshot = nil
      true
    end

    # The person's data the receipt names: from the snapshot of the first
    # document made, or current while none is.
    def snapshot = @snapshot ||= DeregistrationSnapshot.for(person)

    def generated_on_text = I18n.l(created_on)

    def generated_by_name = creator&.full_name.to_s

    # The three kinds as the receipt spells them: the sys input the template
    # branches on, the word in the file name, the abbreviation in the booking
    # text and the wording of the remittance information (SEPA-safe ASCII).
    KIND_TEXTS = {
      "withdrawal" => {word: "Abmeldung", abbrev: "Abm.", wording: "Rueckzahlung nach Abmeldung"},
      "termination" => {word: "Kündigung", abbrev: "Kuend.", wording: "Rueckzahlung nach Kuendigung"},
      "cancellation" => {word: "Storno", abbrev: "Storno", wording: "Rueckzahlung nach Storno"}
    }.freeze

    def kind = person.deregistration_kind_or_default

    def kind_word = kind_texts[:word]

    def kind_abbrev = kind_texts[:abbrev]

    def wording = kind_texts[:wording]

    def role = snapshot.role

    # The role as the contract writes it ("International Service Team
    # Mitglied"), so the receipt and the contract say the same thing.
    def role_name = snapshot.role_name

    def role_id = "#{role} #{person.id}"

    def team_unit = snapshot.team_unit

    # What the creditor the refund is paid to is called in Moss -- the same
    # name the page's creditor section states.
    def creditor_name = RefundCreditor.new(person).name

    def ticket = person.deregistration_issue.to_s.strip

    def booking_text
      @booking_text ||= begin
        room = BOOKING_TEXT_MAX - booking_text_with("").length - 1
        booking_text_with((room >= 1) ? person.name_within(room) : "")
      end
    end

    # The longest name whose transliterated line still fits. Each round either
    # returns or shrinks the room by at least one character, so this ends --
    # at worst with no name at all.
    def purpose
      @purpose ||= begin
        room = PURPOSE_MAX - SepaText.transliterate(purpose_with("")).length - 1
        text = nil
        while room >= 1
          name = person.name_within(room)
          text = SepaText.transliterate(purpose_with(name))
          break if text.length <= PURPOSE_MAX

          room = name.length - 1
          text = nil
        end
        text || SepaText.limit(purpose_with(""), PURPOSE_MAX)
      end
    end

    def amount_cents = person.deregistration_refund_cents

    def amount_text = format_cents_de(amount_cents, zero_cents: ",00")

    def total_fee_text = format_cents_de(person.total_fee_cents, zero_cents: ",00")

    # The fee the way the contract states it -- the euro amount without cents,
    # and with the reason behind it where the fee was reduced for one.
    def total_fee_contract_text = person.total_fee_eur_text

    # Why the fee is not the regular one: what the reduction was granted for,
    # or how much it was where nobody wrote a reason. Nil where the fee is the
    # regular one.
    def fee_reason
      reduction = person.active_total_fee_reduction
      return nil if reduction.zero?

      person.active_total_fee_reduction_hint.presence&.squish ||
        "reduziert um #{format_eur_de(reduction, space: "", zero_cents: "")}"
    end

    # What the fee is called on the page and in the paragraph -- plain text,
    # not the markup Person#total_fee_label builds for the finance views.
    def total_fee_label
      reason = fee_reason
      reason ? "Beitrag (#{reason})" : "Beitrag"
    end

    def amount_paid_text = format_cents_de(person.amount_paid_cents, zero_cents: ",00")

    # What the page's Entschädigung row shows: the amount that was agreed on,
    # or the bracket of section 7.2 T&R while none was.
    def compensation_cents
      person.deregistration_actual_compensation_cents ||
        person.deregistration_contractual_compensation_cents
    end

    def compensation_text = format_cents_de(compensation_cents, zero_cents: ",00")

    def requested_date_text = date_text(person.deregistration_requested_date)

    def effective_date_text = date_text(person.deregistration_effective_date)

    def account_holder = SepaAccount.account_holder(snapshot.sepa)

    # Normalized the way the SEPA exports write it, so what is read off the
    # page can be typed into online banking as it stands.
    def iban = SepaAccount.iban(snapshot.sepa)

    def to_sys_inputs
      {
        title: title,
        greeting: greeting,
        generated_on: generated_on_text,
        generated_by: generated_by_name,
        show_explanation: show_explanation?,
        kind: kind,
        role_name: role_name,
        person_name: person.full_name,
        person_id: person.id,
        team_unit: team_unit,
        creditor_name: creditor_name,
        total_fee: total_fee_contract_text,
        amount_paid: amount_paid_text,
        compensation: compensation_text,
        refund: amount_text,
        booking_text: booking_text,
        requested_date: requested_date_text,
        requested_date_label: person.deregistration_requested_date_label,
        effective_date: effective_date_text,
        ticket: ticket,
        amount: amount_text,
        purpose: purpose,
        account_holder: account_holder,
        iban: iban
      }.transform_values(&:to_s)
    end

    def to_pdf = TypstDocument.compile_pdf(TEMPLATE, sys_inputs: to_sys_inputs)

    # The first page as a picture, for the preview on the Abmeldung page.
    def to_png(ppi: TypstDocument::THUMBNAIL_PPI)
      TypstDocument.compile_png(TEMPLATE, sys_inputs: to_sys_inputs, ppi: ppi)
    end

    # The name reads as the document is called, umlauts and all.
    def file_name
      TypstDocument.safe_file_name(
        "WSJ27 #{kind_word} #{role} #{person.id} #{person.short_full_name} Rückzahlung.pdf"
      )
    end

    # A made receipt answers its stored figures; amount_cents comes back as
    # the integer it was.
    module Frozen
      FROZEN.each do |key|
        define_method(key) do
          stored = person.deregistration_receipt_snapshot
          return super() unless stored.is_a?(Hash) && stored.key?(key)

          (key == "amount_cents") ? stored[key].to_i : stored[key]
        end
      end
    end
    prepend Frozen

    private

    def kind_texts = KIND_TEXTS.fetch(kind, KIND_TEXTS["withdrawal"])

    # A name cut to its room can end on the space of its initials, which the
    # join would double -- so the parts are stripped before they are joined.
    def booking_text_with(name)
      ["#{kind_abbrev} #{role_id}", name.to_s.strip.presence, ticket.presence].compact.join(" ")
    end

    def purpose_with(name)
      [role_id, name.to_s.strip.presence, "/ WSJ27 #{wording}", ticket.presence].compact.join(" ")
    end

    def date_text(date) = date ? I18n.l(date) : ""
  end
end
