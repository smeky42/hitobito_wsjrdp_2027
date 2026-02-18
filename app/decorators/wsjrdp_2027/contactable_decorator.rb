# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027::ContactableDecorator
  def all_additional_emails(only_public = true)
    additional_emails_array = additional_emails.to_a
    emails = additional_emails_array.collect(&:email).compact_blank.map(&:downcase)
    emails << email.downcase if email.present?
    [[:sepa_mail, "SEPA", false], [:wsjrdp_email, "wsjrdp", false], [:moss_email, "Moss", false]].each do |attr, label, allow_duplicate|
      next unless respond_to?(attr)
      email_addr = send(attr)
      next if email_addr.blank?
      email_addr_norm = email_addr.downcase
      if allow_duplicate || !emails.include?(email_addr_norm)
        additional_email = AdditionalEmail.new(label: label, email: email_addr)
        additional_email.readonly!
        additional_emails_array << additional_email
        emails << email_addr_norm
      end
    end
    nested_values(additional_emails_array, only_public) do |email|
      h.mail_to(email)
    end
  end
end
