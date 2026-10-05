# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The URLs, the permission rule and the Turbo targets of the buttons that link
# a camt transaction or a Moss booking to a person (SubjectLinking), shared by
# every view that shows them -- the camt statement, the Moss wallet, the Moss
# transaction lists and the block a Fin::MossBookingsController action
# re-renders on its own.
module Fin::SubjectLinkingHelper
  def link_subject_path(tx, subject)
    "#{url_for(tx)}/link_subject/#{subject.id}/#{subject.class.name}"
  end

  def disallow_link_subject_path(tx, subject)
    "#{url_for(tx)}/disallow_link_subject/#{subject.id}/#{subject.class.name}"
  end

  def link_subject_and_create_accounting_entry_path(tx, subject)
    "#{url_for(tx)}/link_subject_and_create_accounting_entry/#{subject.id}/#{subject.class.name}"
  end

  # Whether the linking buttons for `subject` are offered: the user must be
  # allowed to change the transaction AND the person -- the same rule the
  # server enforces (SubjectLinking, create_accounting_entry,
  # link_accounting_entry), so no button is shown that would be refused.
  def may_link_subject?(tx_class, subject)
    subject.present? && can?(:update, tx_class) && can?(:update, subject)
  end

  # Whether a button that CREATES a Beitragsbuchung for `subject` is offered:
  # linking rights plus :create on AccountingEntry -- what
  # create_accounting_entry and link_subject_and_create_accounting_entry
  # authorize.
  def may_create_accounting_entry?(tx_class, subject)
    may_link_subject?(tx_class, subject) && can?(:create, AccountingEntry)
  end

  # The existing Beitragsbuchungen named in place of the create-in-one-step
  # button: "#123, #456", each a link for whoever may open it.
  def matching_accounting_entry_links(entries)
    safe_join(entries.map { |entry| link_to_if(fin_entry_details_visible?(entry), "##{entry.id}", entry) }, ", ")
  end

  # The people the buttons offer for `tx`: its candidates from the texts
  # (WsjrdpTransaction#subject_candidates) that the user may link. Empty for
  # the read tier. Each call looks the people up again -- a caller that needs
  # them twice (decide, then render) passes them on as the partial's
  # `candidates` local.
  def subject_link_candidates(tx)
    return [] unless can?(:update, tx.class)

    tx.subject_candidates.select { |candidate| may_link_subject?(tx.class, candidate) }
  end

  # Whether a Moss booking's linking block (fin/moss_bookings/_subject_links)
  # has anything to show: a linked contribution booking, a linked person or a
  # person to offer.
  def moss_booking_subject_links?(booking, candidates = subject_link_candidates(booking))
    booking.accounting_entries.any? || booking.subject.present? || candidates.any?
  end

  # The value of the data attribute that marks every occurrence of a booking's
  # linking block on a page. The link actions replace ALL of them in one Turbo
  # Stream (`replace_all` on #moss_booking_subject_links_selector) -- the same
  # booking may show in more than one table of a page, so an id would not do.
  def moss_booking_subject_links_key(booking)
    dom_id(booking)
  end

  def moss_booking_subject_links_selector(booking)
    "[data-subject-links='#{moss_booking_subject_links_key(booking)}']"
  end

  # The open (already loaded) detail frames of a record, for the `reload_frames`
  # stream action: the expandable table marks each lazily loaded detail frame
  # with its row's dom_id (data-record), and only a frame that has loaded
  # carries `complete` -- one never opened loads fresh anyway.
  def loaded_detail_frames_selector(record)
    "turbo-frame[data-record='#{dom_id(record)}'][complete]"
  end
end
