# frozen_string_literal: true

module ContractHelper
  include ActionView::Helpers::NumberHelper

  extend ActiveSupport::Concern

  # rubocop:disable Layout/ExtraSpacing
  # rubocop:disable Layout/SpaceInsideArrayLiteralBrackets
  # rubocop:disable Layout/HashAlignment
  PAYMENT_ROLE_TO_INSTALLMENTS_CENTS = {
    "RegularPayer::Group::Unit::Member" => [
      [[2025, 12].freeze, 30000].freeze,
      [[2026,  1].freeze, 50000].freeze,
      [[2026,  2].freeze, 50000].freeze,
      [[2026,  3].freeze, 50000].freeze,
      [[2026,  8].freeze, 40000].freeze,
      [[2026, 11].freeze, 40000].freeze,
      [[2027,  2].freeze, 40000].freeze,
      [[2027,  5].freeze, 40000].freeze
    ].freeze,
    "RegularPayer::Group::Unit::Leader" => [
      [[2025, 12].freeze, 15000].freeze,
      [[2026,  1].freeze, 35000].freeze,
      [[2026,  2].freeze, 35000].freeze,
      [[2026,  3].freeze, 35000].freeze,
      [[2026,  8].freeze, 30000].freeze,
      [[2026, 11].freeze, 30000].freeze,
      [[2027,  2].freeze, 30000].freeze,
      [[2027,  5].freeze, 30000].freeze
    ].freeze,
    "RegularPayer::Group::Ist::Member" => [
      [[2025, 12].freeze, 20000].freeze,
      [[2026,  1].freeze, 40000].freeze,
      [[2026,  2].freeze, 40000].freeze,
      [[2026,  3].freeze, 40000].freeze,
      [[2026,  8].freeze, 30000].freeze,
      [[2026, 11].freeze, 30000].freeze,
      [[2027,  2].freeze, 30000].freeze,
      [[2027,  5].freeze, 30000].freeze
    ].freeze,
    "RegularPayer::Group::Root::Member" => [
      [[2025, 12].freeze,  5000].freeze,
      [[2026,  1].freeze, 25000].freeze,
      [[2026,  2].freeze, 25000].freeze,
      [[2026,  3].freeze, 25000].freeze,
      [[2026,  8].freeze, 20000].freeze,
      [[2026, 11].freeze, 20000].freeze,
      [[2027,  2].freeze, 20000].freeze,
      [[2027,  5].freeze, 20000].freeze
    ].freeze,
    "EarlyPayer::Group::Unit::Member" => [ [[2025, 8].freeze, 340000].freeze ].freeze,
    "EarlyPayer::Group::Unit::Leader" => [ [[2025, 8].freeze, 240000].freeze ].freeze,
    "EarlyPayer::Group::Ist::Member" =>  [ [[2025, 8].freeze, 260000].freeze ].freeze,
    "EarlyPayer::Group::Root::Member" => [ [[2025, 8].freeze, 160000].freeze ].freeze
  }.freeze
  # rubocop:enable Layout/ExtraSpacing
  # rubocop:enable Layout/SpaceInsideArrayLiteralBrackets
  # rubocop:enable Layout/HashAlignment

  GOOD_CONDUCT_MISSING_TAG = "eFZ-Einsicht-fehlt"

  included do
    # rubocop:disable Metrics/MethodLength
    def payment_array
      [
        ["Rolle", "Gesamt", "Dez 2025", "Jan 2026", "Feb 2026", "Mär 2026", "Aug 2026", "Nov 2026", "Feb 2027", "Mai 2027"],
        ["RegularPayer::Group::Unit::Member", "3400", "300", "500", "500", "500", "400", "400", "400", "400"],
        ["RegularPayer::Group::Unit::Leader", "2400", "150", "350", "350", "350", "300", "300", "300", "300"],
        ["RegularPayer::Group::Ist::Member", "2600", "200", "400", "400", "400", "300", "300", "300", "300"],
        ["RegularPayer::Group::Root::Member", "1600", "50", "250", "250", "250", "200", "200", "200", "200"],
        ["EarlyPayer::Group::Unit::Member", "3400", "", "", "", "", "", "", "", ""],
        ["EarlyPayer::Group::Unit::Leader", "2400", "", "", "", "", "", "", "", ""],
        ["EarlyPayer::Group::Ist::Member", "2600", "", "", "", "", "", "", "", ""],
        ["EarlyPayer::Group::Root::Member", "1600", "", "", "", "", "", "", "", ""]
      ]
    end
    # rubocop:enable Metrics/MethodLength

    # each person has a primary group which defines the price and role type
    def role_type(person)
      roles = PersonDecorator.new(person).current_roles_grouped
      # If no role could be detected, fallback should be Youth Participant
      role = "Group::Unit::Member"

      # Last assigned role_type in primary group
      roles.each do |key, value|
        value.each do |item|
          if item.group_id == person.primary_group_id
            role = item.type
          end
        end
      end
      role
    end

    def role_full_name(role)
      I18n.t("people.print.contract_roles.#{role.gsub("::", ".")}")
    end

    def payment_role_full_name(role)
      role_full_name(role.split("::", 2)[1])
    end

    def person_payment_role_full_name(person)
      role = build_payment_role(person)
      role_full_name(role.split("::", 2)[1])
    end

    # rubocop:disable Metrics/MethodLength
    def build_payment_role(person)
      role = role_type(person)
      payment_role_name = "RegularPayer"

      if person.early_payer
        payment_role_name = "EarlyPayer"
      end

      payment_role_name += if (role == "Group::Unit::UnapprovedLeader") || (role == "Group::Unit::Leader")
        "::Group::Unit::Leader"
      elsif role == "Group::Unit::Member"
        "::Group::Unit::Member"
      elsif role == "Group::Ist::Member"
        "::Group::Ist::Member"
      else
        "::Group::Root::Member"
      end
      payment_role_name
    end
    # rubocop:enable Metrics/MethodLength

    def cmt?(person)
      if person.payment_role.nil?
        person.payment_role = build_payment_role(person)
      end
      person.payment_role.ends_with?("Root::Member")
    end

    def ul?(person)
      if person.payment_role.nil?
        person.payment_role = build_payment_role(person)
      end
      person.payment_role.ends_with?("Unit::Leader")
    end

    def yp?(person)
      if person.payment_role.nil?
        person.payment_role = build_payment_role(person)
      end
      person.payment_role.ends_with?("Unit::Member")
    end

    def ist?(person)
      if person.payment_role.nil?
        person.payment_role = build_payment_role(person)
      end
      person.payment_role.ends_with?("Ist::Member")
    end

    # rubocop:disable Metrics/MethodLength
    def short_wsj_role(person)
      if person.payment_role.nil?
        person.payment_role = build_payment_role(person)
      end
      if person.payment_role.ends_with?("Unit::Member")
        "YP"
      elsif person.payment_role.ends_with?("Unit::Leader")
        "UL"
      elsif person.payment_role.ends_with?("Ist::Member")
        "IST"
      elsif person.payment_role.ends_with?("Root::Member")
        "CMT"
      else
        "???"
      end
    end
    # rubocop:enable Metrics/MethodLength

    def select_person_for_buddy_id(buddy_id)
      return [] if buddy_id.blank?
      spice, _, id = buddy_id.rpartition("-")
      Person.where(id: id, buddy_id: spice).to_a
    end

    def full_rdp_association_group(person)
      [
        person.rdp_association,
        person.rdp_association_region,
        person.rdp_association_sub_region,
        person.rdp_association_group
      ].map { |s| s.presence || "Nicht gesetzt" }.join(" - ")
    end

    def valid_unit_code?(unit_code)
      if unit_code.blank?
        false
      else
        !!(/^#?[0-9A-Fa-f]{6}$/ =~ unit_code)
      end
    end

    def normalized_unit_code_or_nil(unit_code)
      if unit_code.nil? || unit_code.blank?
        nil
      elsif !!(/^#[0-9A-Fa-f]{6}$/ =~ unit_code)
        unit_code.upcase
      elsif !!(/^[0-9A-Fa-f]{6}$/ =~ unit_code)
        "#" + unit_code.upcase
      end
    end

    def normalized_unit_code(unit_code)
      normalized_unit_code_or_nil(unit_code) || unit_code
    end

    # rubocop:disable Metrics/MethodLength
    def make_unit_code_display(unit_code, search_link: false, attribute: "unit_code")
      norm_unit_code = normalized_unit_code_or_nil(unit_code)
      if norm_unit_code
        color_marker = "<span style=\"display: inline-block; width: 12px; background-color: #{norm_unit_code};'\">&nbsp;</span>".html_safe
        if search_link
          unit_code_search_link = attribute_search_path(1, attribute, unit_code)
          "<a href=\"#{unit_code_search_link}\" style=\"color: inherit;\">#{color_marker} <span style=\"text-decoration: underline;\">#{unit_code}</span></a>".html_safe
        else
          color_marker + " " + unit_code
        end
      else
        unit_code
      end
    end
    # rubocop:enable Metrics/MethodLength

    def attribute_search_path(group, key, value, constraint = "equal")
      quoted_key = URI.encode_uri_component key
      quoted_value = URI.encode_uri_component value
      "/groups/#{group}/people?filters[attributes][0][constraint]=#{constraint}&filters[attributes][0][key]=#{quoted_key}&filters[attributes][0][value]=#{quoted_value}&filters[role][kind]=active_today&range=deep"
    end

    def tag_search_path(group, tag)
      tag_name = tag.to_s
      quoted_tag_name = URI.encode_uri_component tag_name
      "/groups/#{group}/people?filters[role][kind]=active_today&filters[tag][names][]=#{quoted_tag_name}&range=deep"
    end

    def early_payer?(person)
      if person.payment_role.nil?
        person.payment_role = build_payment_role(person)
      end
      person.payment_role.start_with?("EarlyPayer")
    end

    def payment_array_by(person)
      role = if person.payment_role.nil?
        build_payment_role(person)
      else
        person.payment_role
      end
      payment_array.find { |row| row[0] == role }
    end

    def payment_value(person)
      payment_array_by(person)[1]
    end

    def payment_value_cents(person)
      payment_array_by(person)[1].to_i * 100
    end

    def get_full_regular_fee_eur(person)
      payment_array_by(person)[1]
    end

    def get_full_regular_fee_cents(person)
      payment_array_by(person)[1].to_i * 100
    end

    def get_total_fee_cents(person, fee_rule = nil)
      full_regular_fee = payment_array_by(person)[1].to_i * 100
      total_fee = full_regular_fee
      if fee_rule && fee_rule.status == "active" && fee_rule.person == person
        total_fee -= fee_rule.total_fee_reduction_cents || 0
      end
      total_fee
    end

    def regular_installments_cents_for(person)
      role = (person.payment_role.nil? ? build_payment_role(person) : person.payment_role)
      PAYMENT_ROLE_TO_INSTALLMENTS_CENTS[role]
    end

    def get_installments_cents(person, fee_rule = nil)
      installments = fee_rule&.get_installments_cents_if_active
      if installments
        installments
      elsif person.early_payer
        [[[2025, 8], get_total_fee_cents(person, fee_rule)]]
      else
        regular_installments_cents_for(person).dup
      end
    end

    # rubocop:disable Metrics/MethodLength
    def payment_array_sepa
      array = []

      payment_array.each_with_index do |row, row_index|
        if row_index == 0
          array[0] = row
        else
          new_row = []
          row.each_with_index do |element, index|
            if index == 0
              new_row[index] = role_full_name(element.split("::", 2)[1])
            elsif !element.blank?
              new_row[index] = "#{element} €"
            end
          end
          array[row_index] = new_row
        end
      end

      array
    end
    # rubocop:enable Metrics/MethodLength

    def payment_array_table(person)
      array = payment_array_by(person)

      array.each_with_index do |element, index|
        if index == 0
          array[index] = role_full_name(array[0].split("::", 2)[1])
        elsif !array[index].blank?
          array[index] = "#{array[index]} €"
        end
      end

      [payment_array[0], array]
    end

    def format_cents_de(cents, currency = "EUR")
      if currency == "EUR"
        currency = "€"
      end
      number = cents.to_f / 100.0
      number_to_currency(number, separator: ",", delimiter: ".", unit: currency, format: "%n %u").sub(",00", ",—")
    end

    # rubocop:disable Metrics/MethodLength
    def fetch_fee_rules(person)
      active_fee_rule = nil
      planned_fee_rule = nil
      fee_rules = Wsj27RdpFeeRule.where(people_id: person.id, deleted_at: nil)
      fee_rules.each do |fee_rule|
        if fee_rule.status == "active"
          active_fee_rule = fee_rule
        elsif fee_rule.status == "planned"
          planned_fee_rule = fee_rule
        else
          Rails.logger.warning "Unsupported status in fee_rule: #{fee_rule.inspect}"
        end
      end
      [active_fee_rule, planned_fee_rule]
    end
    # rubocop:enable Metrics/MethodLength
  end
end
