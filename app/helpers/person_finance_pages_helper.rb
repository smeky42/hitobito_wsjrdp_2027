# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Who sees a person's finance pages and their tabs -- the same rules as the
# controllers behind them check.
module PersonFinancePagesHelper
  # The anchors of the Beitrag page's sections, with the person's id: unique
  # wherever sections of several people share a page (the finance lists).
  def payment_plan_anchor(person) = "payment_plan_#{person.id}"

  def total_fee_anchor(person) = "total_fee_#{person.id}"

  # What the SEPA mandate still lacks, as labels; empty when it can be made.
  def sepa_mandate_missing_labels(person)
    Wsjrdp2027::SepaMandateRequirements.missing(person).map do |attr|
      (attr == :payment_plan) ? t("people.sepa_account.mandate_missing_plan") : Person.human_attribute_name(attr)
    end
  end

  # Where the "Kontoverbindung" section's button or form stands.
  def bank_account_actions_id(person) = "bank_account_actions_#{person.id}"

  # The notice of the last bank account change, for that person's section.
  def bank_account_notice(person)
    notice = flash[:bank_account_notice]
    notice["text"] if notice.is_a?(Hash) && notice["person_id"].to_s == person.id.to_s
  end

  # The Finanzen tab: whoever may see the person, and the finance audit tier,
  # which reads the Beitrag page (:show_finance) without seeing the person
  # otherwise.
  def person_finance_tab_visible?(person)
    can?(:show, person) || can?(:show_finance, person)
  end

  # The Beitrag page (Person::FeeController): whoever may edit the person --
  # the person themselves, a unit leader for the people of the unit --, and
  # read-only the finance audit tier (:show_finance).
  def person_fee_page_visible?(person)
    can?(:edit, person) || can?(:show_finance, person)
  end

  # The Ausgaben (Moss) page (Person::SpendController): the person themselves
  # -- it carries their own Moss login --, whoever may :log the person, and
  # the finance write tier (:update_finance). Not a unit leader.
  def person_spend_visible?(person)
    person == current_user || can?(:log, person) || can?(:update_finance, person)
  end
end
