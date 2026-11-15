# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027
  # What bestätigung_abmeldung.py reports once it has sent the confirmation of
  # a deregistration (POST /people/:id/deregistration/confirmation_sent.json):
  # like a sent form (DeregistrationFormSent), a log entry of CATEGORY and an
  # event (notify, action ACTION) holding the mail, and the row moves on to
  # confirmation_sent. No person note -- the script writes its own -- and no
  # form needs to be made: a confirmation also ends a termination or a
  # cancelled registration.
  class DeregistrationConfirmationSent < DeregistrationFormSent
    CATEGORY = "deregistration_confirmation"
    ACTION = "confirmation_sent"
    # The steps a confirmation moves a row on from.
    OPEN_STATUSES = %w[recorded form_created form_sent signed_form_received refund_initiated refund_booked].freeze

    def action = ACTION

    def category = CATEGORY

    def person_note? = false

    # The slot of the confirmation's EML: confirmation_mail <n>.
    def mail_secondary_key = "confirmation_mail"

    private

    def form_required? = false

    def recorded!
      return unless OPEN_STATUSES.include?(row.status)

      row.status = "confirmation_sent"
      ::PaperTrail.request(enabled: false) { row.save!(validate: false) }
    end

    def after_recorded!
    end
  end
end
