# frozen_string_literal: true

require "iban-tools"
require "geocoder"

module Wsjrdp2027::Person
  include ContractHelper

  # This is just local to this module, it doesn't override anything when this module in included
  GENDERS = %w[m w d].freeze
  BUDDY_ID_FORMAT = /^(?<tag>[a-zA-Z0-9_äöüÄÖÜß]+-[a-zA-Z0-9_äöüÄÖÜß]+)-(?<id>\d+)$/

  def self.included(base)
    rdp_attrs = [:status, :early_payer, :rdp_association, :rdp_association_region, :rdp_association_sub_region, :rdp_association_group, :unit_code, :cluster_code]
    Person::PUBLIC_ATTRS += rdp_attrs
    Person::FILTER_ATTRS += rdp_attrs
    Person.used_attributes += rdp_attrs

    base.extend Geocoder::Model::Base

    # This hack is needed to make Person::GENDERS return the right value
    base.send(:remove_const, :GENDERS) if base.const_defined?(:GENDERS)
    base.const_set(:GENDERS, GENDERS)

    base.class_eval do
      # We need to remove the existing validator with just two genders first
      _validators[:gender].reject! { |v| v.is_a? ActiveModel::Validations::InclusionValidator }
      # ...and the callback for the validator
      cb = _validate_callbacks.find { |c| c.filter.is_a? ActiveModel::Validations::InclusionValidator and c.filter.attributes.include? :gender }
      _validate_callbacks.delete(cb)

      # Then add the attr with validator and the setter again
      i18n_enum :gender, GENDERS
      i18n_setter :gender, (GENDERS + [nil])

      validate :validate_iban_format
      validate :validate_buddy_id_ul
      validate :validate_buddy_id_yp

      before_save :geocode_full_address, if: :address_changed?
      before_save :tag_good_conduct_missing, if: :status_changed?
      after_save :_save_planned_fee_rule, if: :planned_fee_rule_changed?

      def unit_code_display
        make_unit_code_display(unit_code)
      end

      def cluster_code_display
        make_unit_code_display(cluster_code)
      end

      def short_full_name
        first_names = first_name ? first_name.split : []
        name_parts = if !nickname.blank? && Set.new(first_names).include?(nickname)
          [nickname, last_name]
        else
          [first_names[0], last_name]
        end
        name_parts.select { |s| !s.blank? }.join(" ")
      end

      def short_full_name_with_nickname
        first_names = first_name ? first_name.split : []
        name_parts = if !nickname.blank? && Set.new(first_names).include?(nickname)
          [nickname, last_name]
        elsif nickname.blank?
          [first_names[0], last_name]
        else
          [first_names[0], last_name, "/", nickname]
        end
        name_parts.select { |s| !s.blank? }.join(" ")
      end

      def upload_complete?
        # Checks if the upload is complete
        #
        # New since 2025-11-14: The good conduct document is not
        # required for IST to consider the upload to be complete.
        if ul?(self) || cmt?(self)
          if upload_good_conduct_pdf.nil?
            return false
          end
        end

        if ul?(self) || cmt?(self)
          if upload_data_agreement_pdf.nil?
            return false
          end
        end

        if ul?(self)
          if upload_recommendation_pdf.nil?
            return false
          end
        end

        %i[upload_contract_pdf upload_sepa_pdf upload_medical_pdf upload_passport_pdf upload_photo_permission_pdf]
          .all? { |fld| public_send(fld).present? }
      end

      #
      # active fee rule
      #

      def _maybe_fetch_fee_rules
        if !@fee_rules_fetched
          active_fee_rule, planned_fee_rule = fetch_fee_rules(self)
          @active_fee_rule ||= active_fee_rule
          @planned_fee_rule ||= planned_fee_rule
          @fee_rules_fetched = true
        end
      end

      def active_fee_rule
        _maybe_fetch_fee_rules
        @active_fee_rule
      end

      def active_total_fee_reduction?
        active_fee_rule&.total_fee_reduction?
      end

      def active_total_fee_reduction_cents
        active_fee_rule&.total_fee_reduction_cents || 0
      end

      def active_total_fee_reduction_display
        active_fee_rule&.total_fee_reduction_display || ""
      end

      def active_custom_installments?
        active_fee_rule&.custom_installments?
      end

      def active_custom_installments_display
        active_fee_rule&.custom_installments_display || ""
      end

      def active_custom_installments_string
        active_fee_rule&.custom_installments_string
      end

      def active_custom_installments_issue_display
        active_fee_rule&.custom_installments_issue_display || ""
      end

      def active_custom_installments_comment
        active_fee_rule&.custom_installments_comment
      end

      #
      # planned fee rule
      #

      def planned_fee_rule
        _maybe_fetch_fee_rules
        @planned_fee_rule
      end

      def ensure_planned_fee_rule
        _maybe_fetch_fee_rules
        if @planned_fee_rule.nil?
          @planned_fee_rule = Wsj27RdpFeeRule.new(people_id: id, status: "planned")
        end
        @planned_fee_rule
      end

      def planned_total_fee_reduction?
        planned_fee_rule&.total_fee_reduction?
      end

      def planned_total_fee_reduction_cents
        planned_fee_rule&.total_fee_reduction_cents || 0
      end

      def planned_total_fee_reduction_display
        planned_fee_rule&.total_fee_reduction_display || ""
      end

      def planned_custom_installments?
        planned_fee_rule&.custom_installments?
      end

      # planned_custom_installments_string

      def planned_custom_installments_display
        planned_fee_rule&.custom_installments_display || ""
      end

      def planned_custom_installments_string
        planned_fee_rule&.custom_installments_string
      end

      def planned_custom_installments_string=(value)
        ensure_planned_fee_rule.custom_installments_string = value
      end

      def planned_custom_installments_string_changed?
        planned_fee_rule&.custom_installments_string_changed?
      end

      # planned_custom_installments_issue

      def planned_custom_installments_issue_display
        planned_fee_rule&.custom_installments_issue_display || ""
      end

      def planned_custom_installments_issue
        planned_fee_rule&.custom_installments_issue
      end

      def planned_custom_installments_issue=(value)
        ensure_planned_fee_rule.custom_installments_issue = value.presence
      end

      def planned_custom_installments_issue_changed?
        planned_fee_rule&.custom_installments_issue_changed?
      end

      # planned_custom_installments_comment

      def planned_custom_installments_comment
        planned_fee_rule&.custom_installments_comment
      end

      def planned_custom_installments_comment=(value)
        ensure_planned_fee_rule.custom_installments_comment = value.presence
      end

      def planned_custom_installments_comment_changed?
        planned_fee_rule&.custom_installments_comment_changed?
      end

      private

      def validate_iban_format
        return if sepa_iban.blank?

        normalized_iban = sepa_iban.gsub(/\s+/, "").upcase
        unless IBANTools::IBAN.valid?(normalized_iban)
          errors.add(:sepa_iban, I18n.t("people.finance_fields.invalid_iban"))
        end
      end

      def validate_buddy_id(field)
        buddy_id = send(field)
        return nil if buddy_id.blank?

        id_parts = buddy_id.match(BUDDY_ID_FORMAT)
        if id_parts.nil?
          errors.add(field, :invalid)
          return nil
        end

        buddy = Person.find_by(id: id_parts[:id])
        if buddy.nil? ||
            buddy.buddy_id != id_parts[:tag]
          errors.add(field, :invalid)
          return nil
        end

        if buddy == self
          errors.add(field, :buddy_self)
          return nil
        end

        buddy
      end

      def validate_buddy_id_ul
        buddy = validate_buddy_id(:buddy_id_ul)
        return if buddy.nil?

        unless ul?(buddy)
          errors.add(:buddy_id_ul, :buddy_no_ul)
        end
      end

      def validate_buddy_id_yp
        buddy = validate_buddy_id(:buddy_id_yp)
        return if buddy.nil?

        unless yp?(buddy)
          errors.add(:buddy_id_yp, :buddy_no_yp)
        end
      end

      def geocode_full_address
        results = Geocoder.search(full_address)

        if results.first
          self.latitude = results.first.latitude
          self.longitude = results.first.longitude
        end
      end

      def tag_good_conduct_missing
        unless ist?(self) || ul?(self) || cmt?(self)
          return
        end
        Rails.logger.tagged("#{id} #{short_full_name}") do
          tag_name = "eFZ-Einsicht-fehlt"
          Rails.logger.debug { "status=#{status.inspect}" }
          Rails.logger.debug { "upload_good_conduct_pdf.nil?=#{upload_good_conduct_pdf.nil?.inspect}" }
          if upload_good_conduct_pdf.nil?
            # Before save: If self changes to "in_review", "reviewed"
            # or "confirmed" and the good conduct document is missing,
            # we ensure that the eFZ-Einsicht-fehlt tag is set.
            if %w[in_review reviewed confirmed].any?(status)
              Rails.logger.debug ActiveSupport::LogSubscriber.new.send(:color, "Add tag #{tag_name.inspect}", :magenta)
              tag_list.add(tag_name)
            end
          else
            # # Before save: If self changes to "reviewed" and some good
            # # conduct document is present, we ensure that the
            # # eFZ-Einsicht-fehlt tag is not set.
            # if %w[reviewed].any?(status)
            #   Rails.logger.debug ActiveSupport::LogSubscriber.new.send(:color, "Remove tag #{tag_name.inspect}", :magenta)
            #   tag_list.remove(tag_name)
            # end
          end
        end
      end

      def full_address
        [street, housenumber, zip_code, town, country].compact.join(", ")
      end

      def address_changed?
        street_changed? || housenumber_changed? || zip_code_changed? || town_changed? || country_changed?
      end

      def planned_fee_rule_changed?
        if @planned_fee_rule.nil?
          false
        else
          @planned_fee_rule.changes.keys.any? { |k| k != "people_id" && k != "status" }
        end
      end

      def _save_planned_fee_rule
        rule = planned_fee_rule
        if rule.people_id.nil?
          rule.people_id = id
        end
        rule.save
      end
    end
  end
end
