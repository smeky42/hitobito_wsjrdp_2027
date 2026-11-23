# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The kinds of the all-transactions page (Fin::AccountTransaction#kind): four
# for bank transactions, then the Moss kinds. A Moss top-up is a transfer
# between own accounts, so it shares the transfer kind with the bank.
#
# Like Fin::MossKinds this holds the icon and the CSS class; the words are in
# the locale (fin.account_kinds), the colours in shared/wsjrdp/_moss_kind_styles.
module Fin::AccountKinds
  BANK = "bank"
  BANK_RETURN = "bank_return"
  BANK_FEE = "bank_fee"
  TRANSFER = "transfer"

  # The page's own kinds. A transfer takes the colour of the Moss top-up.
  OWN = {
    BANK => {icon: "university", css_class: "#{Fin::MossKinds::CSS_PREFIX}bank"},
    BANK_RETURN => {icon: "ban", css_class: "#{Fin::MossKinds::CSS_PREFIX}bank_return"},
    BANK_FEE => {icon: "percent", css_class: "#{Fin::MossKinds::CSS_PREFIX}bank_fee"},
    TRANSFER => {icon: "exchange-alt", css_class: Fin::MossKinds.css_class("MossTopUp")}
  }.freeze

  # The Moss kinds that keep their own kind here.
  MOSS = %w[MossCardTransaction MossReimbursement MossInvoice].freeze

  ALL = (OWN.keys + MOSS).freeze

  # The kinds a bank account's own transactions can have.
  BANK_KINDS = OWN.keys.freeze

  # The kind of a bank transaction; the first rule that matches wins. A
  # transfer counts once it is linked.
  def self.camt_sql(t)
    "CASE WHEN #{t}.return_kind IS NOT NULL THEN '#{BANK_RETURN}' " \
      "WHEN #{t}.internal_transfer_id IS NOT NULL THEN '#{TRANSFER}' " \
      "WHEN #{t}.bank_transaction_domain = 'ACMT' THEN '#{BANK_FEE}' ELSE '#{BANK}' END"
  end

  def self.moss_sql(t) = "CASE WHEN #{t}.type = 'MossTopUp' THEN '#{TRANSFER}' ELSE #{t}.type END"

  def self.icon(kind) = OWN.dig(kind, :icon) || Fin::MossKinds.icon(kind)

  def self.css_class(kind) = OWN.dig(kind, :css_class) || Fin::MossKinds.css_class(kind)

  def self.label(kind) = I18n.t("#{OWN.key?(kind) ? "fin.account_kinds" : "fin.moss.kind_chips"}.#{kind}")

  def self.hint(kind)
    scope = OWN.key?(kind) ? "fin.account_kind_hints" : "fin.moss.kind_hints"
    I18n.t("#{scope}.#{kind}", default: "").presence
  end

  # [kind, label] pairs for the filter.
  def self.options(kinds = ALL) = kinds.map { |kind| [kind, label(kind)] }

  # The kinds as the fixed group of a page's quick choice
  # (Fin::MossKinds.fixed_group): all of them, or a bank statement's own.
  def self.fixed_group(kinds = ALL)
    members = kinds.map do |kind|
      {key: OWN.key?(kind) ? kind : Fin::MossKinds.slug(kind), label: label(kind), value: kind,
       icon: icon(kind), css_class: "#{Fin::MossKinds::PRESET_CLASS} #{css_class(kind)}"}
    end
    {key: "kind", multiple: true, attribute: "kind", default: members.pluck(:key),
     all_title: "Alle Arten wählen bzw. abwählen", members: members}
  end
end
