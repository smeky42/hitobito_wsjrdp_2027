# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module AccountingEntryHelper
  def format_accounting_entry_direct_debit_pre_notification(ae)
    _format_link_to(ae.direct_debit_pre_notification)
  end

  def format_accounting_entry_camt_transaction(ae)
    _format_link_to(ae.camt_transaction)
  end

  def format_accounting_entry_moss_booking(ae)
    _format_link_to(ae.moss_booking)
  end

  private

  def _format_link_to(obj)
    if obj.nil?
      content_tag(:span, "(keine)", class: "muted")
    elsif obj.respond_to?(:link_name)
      link_to(obj.link_name, obj)
    else
      link_to(obj)
    end
  end
end
