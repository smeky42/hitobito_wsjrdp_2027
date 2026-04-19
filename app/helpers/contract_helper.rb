# frozen_string_literal: true

module ContractHelper
  include ActionView::Helpers::NumberHelper
  include ActionView::Helpers::TextHelper

  extend ActiveSupport::Concern

  GOOD_CONDUCT_MISSING_TAG = "eFZ-Einsicht-fehlt"

  included do
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
      role = person.build_payment_role
      role_full_name(role.split("::", 2)[1])
    end

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
    def make_unit_code_display(unit_code, search_link: false, attribute: "unit_code", not_set_text: nil)
      norm_unit_code = normalized_unit_code_or_nil(unit_code)
      if norm_unit_code
        color_marker = "<span style=\"display: inline-block; width: 12px; background-color: #{norm_unit_code};'\">&nbsp;</span>".html_safe
        if search_link
          unit_code_search_link = attribute_search_path(1, attribute, unit_code)
          "<a href=\"#{unit_code_search_link}\" style=\"color: inherit;\">#{color_marker} <span style=\"text-decoration: underline;\">#{unit_code}</span></a>".html_safe
        else
          color_marker + " " + unit_code
        end
      elsif unit_code.blank? && not_set_text.present?
        "<span class=\"muted fw-light\">#{not_set_text}</span>".html_safe
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

    def html_escape_multiline(s)
      html_escape(s).gsub(/(?:\n\r?|\r\n?)/, "<br/>\n").html_safe
    end

    def auto_link_escaped_multiline(s)
      s = s.gsub(%r{https://helpdesk.worldscoutjamboree.de/(?:browse|projects/HELP/queues/custom/[0-9]+)/([a-zA-Z0-]+-[0-9]+)}, "\\1")
      escaped_s = html_escape_multiline(s).gsub(/\b(?:FIN|HELP)-[0-9]+\b/, "https://helpdesk.worldscoutjamboree.de/browse/\\&")
      auto_link(escaped_s, sanitize: false, html: {target: "_blank"}) do |href|
        href.gsub(%r{https://helpdesk.worldscoutjamboree.de/browse/}, "")
      end.html_safe
    end

    def compute_contractual_compensation_cents(cents, today: nil) # rubocop:disable Metrics/MethodLength
      today = Time.zone.today if today.nil?
      today_i = today.strftime("%Y%m%d").to_i
      if today_i >= 20270331
        cents
      elsif today_i >= 20263112
        (0.9 * cents).to_i
      elsif today_i >= 20263105
        (0.75 * cents).to_i
      else
        (0.5 * cents).to_i
      end
    end

    def format_cents_de(cents, currency = "EUR", delimiter: ".", zero_cents: ",—", space: " ", format: nil)
      return nil if cents.blank?
      currency = "€" if currency == "EUR"
      format = "%n#{space}%u" if format.blank?
      number = cents.to_f / 100.0
      number_to_currency(number, separator: ",", delimiter: delimiter, unit: currency, format: format).sub(",00", zero_cents)
    end

    def format_eur_de(eur, currency = "EUR", delimiter: ".", zero_cents: ",—", space: " ", format: nil)
      return nil if eur.blank?
      currency = "€" if currency == "EUR"
      format = "%n#{space}%u" if format.blank?
      number = BigDecimal(eur)
      number_to_currency(number, separator: ",", delimiter: delimiter, unit: currency, format: format).sub(",00", zero_cents)
    end

    # rubocop:disable Metrics/MethodLength
    def fetch_fee_rules(person)
      active_fee_rule = nil
      planned_fee_rule = nil
      fee_rules = Wsj27RdpFeeRule.where(people_id: person.id, deleted_at: nil)
      fee_rules.each do |fee_rule|
        # Set fee_rule.person so that we do not need to load it later
        # on access.
        fee_rule.person = person
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
