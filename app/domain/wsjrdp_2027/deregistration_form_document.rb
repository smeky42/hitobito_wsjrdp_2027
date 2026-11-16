# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027
  # The Abmelde-Formular kept as a document of the deregistration row: the PDF
  # (deregistration <number>, form; key_ref the row) and its first page as a
  # picture beside it (a derivation, THUMBNAIL_DERIVATION_KEY). The row points
  # at the PDF (sent_form_document).
  #
  # The PDF carries the fingerprint of what it was drawn from
  # (DeregistrationForm#inputs_digest, additional_info[DIGEST_KEY]). Before
  # the form went out a kept PDF is the form only while that fingerprint
  # matches: the form prints live data too (the amount paid, names, the
  # guardians), so a payment booked since makes it stale.
  #
  # "PDF erzeugen" on the page keeps it as the form is made; prepare_form.json
  # takes the kept one while it is fresh (#fresh) and keeps a new version
  # otherwise -- it replaces the one before, which stays as superseded --, so
  # the script attaches exactly the stored PDF (form.pdf answers it).
  # form_sent.json needs it and fixes it with the first mail; from then on the
  # stored one stays, whatever the data say.
  #
  # A document write is a locked change of its own: never inside a
  # transaction.
  class DeregistrationFormDocument
    SECONDARY_KEY = "form"
    THUMBNAIL_DERIVATION_KEY = "thumbnail"
    DIGEST_KEY = "form_inputs_sha256"
    DISCARD_REASON = "deregistration form discarded"
    # The slot of the mails the form went out with
    # (DeregistrationFormSent::FORM_MAIL_SECONDARY_KEY), listed with the PDF.
    MAIL_SECONDARY_KEY = "form_mail"

    attr_reader :person, :row

    # The row's documents around the form, the PDF first, then the current
    # mails in the order they went out; none without a row. The PDF is the
    # one the row points at (sent_form_document) while it is not deleted -- a
    # PDF a discarded form left in its slot is no longer the row's, even
    # where hiding it had to wait.
    def self.documents_of(person, row = person.deregistration)
      return WsjrdpDocument.none if row.nil?

      documents = WsjrdpDocument.of_subject(person).originals.where(key: "deregistration", key_number: row.number)
      documents.current.where(secondary_key: MAIL_SECONDARY_KEY)
        .or(documents.visible.where(secondary_key: SECONDARY_KEY, id: row.sent_form_document_id))
        .order(Arel.sql("secondary_key = '#{SECONDARY_KEY}' DESC"), :secondary_key_number, :id)
    end

    # The stored document, where it is there to be used: not deleted, its file
    # on disk and not known missing, and -- unless `current: false` (a form
    # that went out stays the one sent) -- still the current version of its
    # slot, not one an upload replaced. nil otherwise.
    def self.usable(document, current: true)
      return nil if document.nil? || document.status == WsjrdpDocument::DELETED || document.file_missing?
      return nil if current && !document.current?
      return nil unless File.file?(DocumentStore.path_for(document))

      document
    rescue ArgumentError
      nil
    end

    # Hides the form kept for a row whose form did not go out, when the form
    # is discarded: the current PDF of the row's slot and its current
    # derivations (the picture), in one locked change; the files stay. Found
    # by the slot, since the row has let go of it already. Nothing for a row
    # whose form went out.
    def self.hide_unsent!(person, row, by:)
      return if row.nil? || row.form_sent_at

      document = WsjrdpDocument.current_for(person, key: "deregistration", key_number: row.number,
        secondary_key: SECONDARY_KEY, secondary_key_number: 0)
      return unless document

      write = DocumentWrite.new(subject: person)
      [document, *document.derivatives.current].each do |doc|
        write.hide(doc, reason: DISCARD_REASON, by: by)
      end
      write.commit!
    end

    # `form`: the DeregistrationForm of the person where the caller has one
    # already (its inputs are built once).
    def initialize(person, author:, service_token: nil, form: nil)
      @person = person
      @row = person.deregistration
      @author = author
      @service_token = service_token
      @form = form
    end

    # The kept form: once it went out the one sent; before that the kept one
    # while it is fresh, else the form as it stands now, kept as a new
    # version. Answers the PDF document.
    def store!
      return row.sent_form_document if row.form_sent_at

      fresh || write!
    end

    # The kept PDF while it still says what the data say; nil otherwise.
    def fresh
      document = self.class.usable(row&.sent_form_document)
      return nil unless document

      document if document.additional_info.to_h[DIGEST_KEY] == form.inputs_digest
    end

    private

    def form = @form ||= DeregistrationForm.new(person)

    def write!
      document = DocumentStore.store!(StringIO.new(form.to_pdf),
        origin_attributes.merge(subject: person, key: "deregistration", key_number: row.number, key_ref: row,
          secondary_key: SECONDARY_KEY, filename: form.file_name, replaces: current,
          additional_info: {DIGEST_KEY => form.inputs_digest}),
        upload: false)
      row.sent_form_document = document
      ::PaperTrail.request(enabled: false) { row.save!(validate: false) }
      store_thumbnail!(document)
      document
    end

    # The current PDF of the slot, which a new version replaces.
    def current
      WsjrdpDocument.current_for(person, key: "deregistration", key_number: row.number,
        secondary_key: SECONDARY_KEY, secondary_key_number: 0)
    end

    # The first page as a picture, drawn at the same moment from the same
    # data. A picture that cannot be made is no reason to fail: the page then
    # draws it from the data.
    def store_thumbnail!(document)
      DocumentStore.store!(StringIO.new(form.to_png),
        origin_attributes.merge(derived_from: document, derivation_key: THUMBNAIL_DERIVATION_KEY,
          filename: form.file_name.sub(/\.pdf\z/, ".png")),
        upload: false)
    rescue => e
      Rails.logger.warn("DeregistrationFormDocument: no thumbnail for document #{document.id}: #{e.class}: #{e.message}")
      nil
    end

    def origin_attributes
      return {author: @author} unless @service_token

      {author: @author, origin: "api", origin_service_token: @service_token}
    end
  end
end
