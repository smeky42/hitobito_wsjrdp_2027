# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027
  # What a person paid towards their fee, on paper: the entries the fee page
  # lists, in the order and the wording that page uses -- but only those that
  # move money, and without the comments, whoever asks for the document. The
  # statement is meant to be handed on, so it carries nothing that is internal.
  #
  # Everything the template receives is a String; the rows travel as JSON and
  # are placed as text, never as markup. See doc/typst_documents.md.
  class FeeStatement
    include ContractHelper

    TEMPLATE = "fee_statement.typ"

    attr_reader :person, :entries

    def initialize(person, entries:)
      @person = person
      @entries = entries
    end

    def role = person.wsjrdp_role

    def role_id = "#{role} #{person.id}"

    # The scripts' role_id_name: role, registration id and short name.
    def role_id_name = "#{role_id} #{person.short_full_name}"

    # The heading of the Kontoauszug page in the scripts' deregistration
    # confirmation: the word and the role_id_name.
    def title = "Kontoauszug #{role_id_name}"

    def statement_date_text = I18n.l(Date.current)

    def balance_text = eur(person.amount_paid_cents)

    # Booked entries only -- no pre-notifications, whatever their state -- and
    # none that moves no money; newest first, as the scripts sort them:
    # value date, then booking date, then id, all descending.
    def rows
      entries
        .select { |entry| entry.is_a?(AccountingEntry) && entry.amount_cents != 0 }
        .sort_by { |entry| sort_key(entry) }
        .reverse
        .map { |entry| row_for(entry) }
    end

    def to_sys_inputs
      {
        title: title,
        role_id_name: role_id_name,
        statement_date: statement_date_text,
        balance: balance_text,
        entries: rows.to_json
      }.transform_values(&:to_s)
    end

    def to_pdf = TypstDocument.compile_pdf(TEMPLATE, sys_inputs: to_sys_inputs)

    def file_name
      TypstDocument.safe_file_name(
        "WSJ27 Beitragszahlungen #{role} #{person.id} #{person.short_full_name}.pdf"
      )
    end

    private

    # No comment column: comments are internal, whatever the page shows to
    # whom, and they do not even reach the template.
    def row_for(entry)
      {
        "date" => I18n.l(entry.value_date || entry.booking_date || entry.created_at.to_date),
        "description" => entry.description.to_s,
        "short_dbtr" => entry.short_dbtr.to_s,
        "amount" => eur(entry.amount_cents)
      }
    end

    def sort_key(entry)
      fallback = entry.created_at.to_date
      [entry.value_date || entry.booking_date || fallback, entry.booking_date || fallback, entry.id.to_i]
    end

    # The amount as the scripts write it: "1.600,— €" with a non-breaking
    # space before the euro sign, and ",—" for whole euros.
    def eur(cents) = format_cents_de(cents, space: " ")
  end
end
