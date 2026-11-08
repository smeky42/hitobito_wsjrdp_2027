# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Fin::FinAccountsHelper
  # Grouped in blocks of four, the way an IBAN is read. What is stored stays
  # untouched; only the reading aid is added here.
  def fin_account_iban_blocks(iban)
    iban.to_s.delete(" ").scan(/.{1,4}/).join(" ").presence
  end

  # The blocks in figures of one width, so IBANs line up (the list's column says
  # so itself: tabular_nums in Fin::FinAccountsColumns).
  def fin_account_iban_display(iban)
    blocks = fin_account_iban_blocks(iban)
    blocks && content_tag(:span, blocks, style: "font-variant-numeric: tabular-nums")
  end

  # A value with the icon that copies it, through the core's handler for
  # a[data-copy-to-clipboard]. That handler reads the attribute off the clicked
  # element, so _detail takes the icon out of the hit test (.fin-copy).
  def fin_account_copyable(shown, value)
    return nil if value.blank?

    safe_join([shown, link_to(icon(:copy, filled: false), "#", class: "fin-copy text-muted",
      title: t("global.button.copy"), "aria-label": t("global.button.copy"),
      data: {copy_to_clipboard: value.delete(" ")})])
  end

  # The columns of the account list (Fin::FinAccountsColumns) with their cells.
  def fin_accounts_table_columns
    cells = {
      "label" => ->(acc) { fin_accounts_table_label(acc) },
      "servicer" => ->(acc) { acc.servicer_short_name },
      "product" => ->(acc) { acc.account_product_label },
      "iban" => ->(acc) { fin_account_iban_blocks(acc.iban) || acc.account_identification },
      "bookkeeping" => ->(acc) { fin_accounts_table_bookkeeping(acc) },
      "balance" => ->(acc) { fin_aligned_cents_de(fin_accounts_table_balance_cents(acc)) }
    }
    Fin::FinAccountsColumns::COLUMNS.map { |col| col.to_table_column(cell: cells.fetch(col.key)) }
  end

  # The sum row: the balance of every account the list shows, closed ones too.
  def fin_accounts_table_footer(col, rows)
    case col[:key]
    when "label" then "Summe"
    when "balance" then fin_aligned_cents_de(rows.sum { |acc| fin_accounts_table_balance_cents(acc) })
    end
  end

  # What identifies the account in its head line: its IBAN. A wallet has none, so
  # it shows the IBAN it is funded through, saying so, or its bare identification.
  def fin_account_summary_identifier(account)
    if account.iban.present?
      fin_account_iban_display(account.iban)
    elsif account.top_up_iban.present?
      safe_join([fin_account_iban_display(account.top_up_iban), " (#{WsjrdpFinAccount.human_attribute_name(:top_up_iban)})"])
    else
      account.account_identification.presence
    end
  end

  def fin_format_wsjrdp_fin_account_iban(account)
    fin_account_copyable(fin_account_iban_display(account.iban), account.iban)
  end

  def fin_format_wsjrdp_fin_account_top_up_iban(account)
    fin_account_copyable(fin_account_iban_display(account.top_up_iban), account.top_up_iban)
  end

  def fin_format_wsjrdp_fin_account_servicer_bic(account)
    fin_account_copyable(account.servicer_bic, account.servicer_bic)
  end

  def fin_format_wsjrdp_fin_account_top_up_bic(account)
    fin_account_copyable(account.top_up_bic, account.top_up_bic)
  end

  # An account's identification is its IBAN unless it has none (see the column's
  # migration), and then the row would only say the same thing twice.
  def fin_format_wsjrdp_fin_account_account_identification(account)
    identification = account.account_identification
    return {hide: true} if identification.to_s.delete(" ") == account.iban.to_s.delete(" ")

    identification
  end

  def fin_format_wsjrdp_fin_account_account_product(account) = account.account_product_label

  # The label; from the write tier up also the stored value, which is what a
  # query or an import speaks.
  def fin_format_wsjrdp_fin_account_status(account)
    return account.status_display unless can?(:update, account)

    safe_join([account.status_display, " ", content_tag(:span, account.status, class: "text-muted fw-light")])
  end

  def fin_format_wsjrdp_fin_account_opening_balance_eur(account)
    fin_money(account.opening_balance_eur, account.opening_balance_currency)
  end

  def fin_format_wsjrdp_fin_account_bookkeeping_account_number(account)
    number = account.bookkeeping_account_number
    return nil if number.blank?

    target = account.bookkeeping_account
    label = [number, target&.short_name.presence || target&.name].compact_blank.join(" ")
    url = fin_account_bookkeeping_account_url(target)
    url ? safe_join([label, wsjrdp_newtab_link(url)]) : label
  end

  private

  # The name links the account's page; a click on the rest of the row opens its
  # detail.
  def fin_accounts_table_label(account)
    badge = content_tag(:span, "geschlossen", class: "badge text-bg-secondary ms-1") if account.status == "closed"
    safe_join([link_to(fin_account_label(account), wsjrdp_fin_account_path(account)), badge].compact)
  end

  # The number with the account's name, muted -- no link: the row opens the
  # detail, whose Sachkonto row links it.
  def fin_accounts_table_bookkeeping(account)
    target = account.bookkeeping_account
    name = target&.short_name.presence || target&.name
    safe_join([account.bookkeeping_account_number, (content_tag(:span, name, class: "text-muted fw-light ms-1") if name)].compact)
  end

  # `balance_eur` comes from the list's query (Fin::FinAccountsColumns::BALANCE_SQL).
  def fin_accounts_table_balance_cents(account) = (account.balance_eur * 100).round

  # The page of the bookkeeping account, if it exists and the viewer may see it.
  def fin_account_bookkeeping_account_url(target)
    return nil unless target && can?(:show, target)

    case target
    when WsjrdpLedgerAccount then ledger_account_path(target.number)
    when WsjrdpPersonalAccount then personal_account_path(target.number)
    end
  end
end
