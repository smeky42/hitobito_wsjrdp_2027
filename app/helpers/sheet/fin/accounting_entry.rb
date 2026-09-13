# frozen_string_literal: true

#  Copyright (c) 2025 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Sheet
  class Fin::AccountingEntry < Base
    # The class attribute is what the list page uses: Sheet::Base picks the
    # parent sheet for #index, and a list of all bookings belongs to nobody in
    # particular. Where a single entry hangs is decided per entry below.
    self.parent_sheet = Sheet::Fin::Fees

    def title
      "Buchung #{entry.id}"
    end

    # Whether this entry is about somebody. Deliberately the subject and not
    # #person: that one answers with the root user when there is no subject,
    # which would make a form for nobody look like the root user's page.
    def subject?
      entry.subject_id.present?
    end

    # A form for a new entry may not have a person yet -- then there is no
    # person page to point the parent nav at, and the sheet's own path does.
    def current_parent_nav_path
      subject? ? view.person_accounting_path(entry.person) : super
    end

    # An entry belongs to a person, and its page sits under that person's.
    # The form for a new one may not have one yet; it then sits under
    # Beiträge, the section these bookings belong to, which needs neither a
    # person nor a group.
    def parent_sheet
      @parent_sheet ||= create_parent(subject? ? Sheet::Person : Sheet::Fin::Fees)
    end
  end
end
