# frozen_string_literal: true

require "iban-tools"
require "geocoder"

module Wsjrdp2027::Person
  include ContractHelper

  # This is just local to this module, it doesn't override anything when this module in included
  GENDERS = %w[m w d].freeze
  BUDDY_ID_FORMAT = /^(?<tag>[a-zA-Z0-9_äöüÄÖÜß]+-[a-zA-Z0-9_äöüÄÖÜß]+)-(?<id>\d+)$/

  WSJRDP_ATTRS = [
    :status, :early_payer,
    :rdp_association, :rdp_association_region, :rdp_association_sub_region, :rdp_association_group,
    :unit_code, :cluster_code,
    :additional_info,
    :zero_padded_id
  ].freeze

  WSJRDP_SEARCHABLE_ATTRS = [
    :id,
    :additional_contact_name_a, :additional_contact_adress_a, :additional_contact_email_a, :additional_contact_phone_a,
    :additional_contact_name_b, :additional_contact_adress_b, :additional_contact_email_b, :additional_contact_phone_b,
    :sepa_name, :sepa_address, :sepa_mail, :sepa_iban
  ]

  def self.included(base)
    # Be careful to modify existing variables instead of re-assigning
    # them to avoid Ruby warnings.
    Person::PUBLIC_ATTRS.concat(WSJRDP_ATTRS)
    Person::FILTER_ATTRS.concat(WSJRDP_ATTRS)
    Person.used_attributes.concat(WSJRDP_ATTRS)
    # Searching for birthdays interferes too much with searching for a
    # persons id, so we remove :birthday from SEARCHABLE_ATTRS.
    Person::SEARCHABLE_ATTRS.delete :birthday
    Person::SEARCHABLE_ATTRS.concat(WSJRDP_SEARCHABLE_ATTRS)

    base.extend Geocoder::Model::Base

    # This hack is needed to make Person::GENDERS return the right value
    base.send(:remove_const, :GENDERS) if base.const_defined?(:GENDERS)
    base.const_set(:GENDERS, GENDERS)

    base.class_eval do
      include WsjrdpJsonbHelper
      include WsjrdpNumberHelper

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

      jsonb_accessor :additional_info, :debit_return_issue, strip: true
      jsonb_accessor :additional_info, :wsjrdp_email, strip: true, created_at_key: :wsjrdp_email_created_at, updated_at_key: :wsjrdp_email_updated_at
      jsonb_accessor :additional_info, :wsjrdp_email_created_at
      jsonb_accessor :additional_info, :wsjrdp_email_updated_at
      jsonb_accessor :additional_info, :moss_email, strip: true, created_at_key: :moss_email_created_at, updated_at_key: :moss_email_updated_at
      jsonb_accessor :additional_info, :moss_email_created_at
      jsonb_accessor :additional_info, :moss_email_updated_at

      jsonb_accessor :additional_info, :deregistration_issue, strip: true
      jsonb_accessor :additional_info, :deregistration_effective_date
      jsonb_accessor :additional_info, :deregistration_actual_compensation_cents
      attribute :deregistration_effective_date, :date
      attribute :deregistration_actual_compensation_cents, :integer

      eur_attribute :total_fee_eur, cents_attr: :total_fee_cents
      eur_attribute :amount_paid_eur, cents_attr: :amount_paid_cents
      eur_attribute :deregistration_actual_compensation_eur, cents_attr: :deregistration_actual_compensation_cents

      def short_full_name
        first_names = first_name ? first_name.split : []
        name_parts = if !nickname.blank? && Set.new(first_names).include?(nickname)
          [nickname, last_name]
        else
          [first_names[0], last_name]
        end
        name_parts.select { |s| !s.blank? }.join(" ")
      end

      def status_log_display
        [Settings.status[status].presence, "(#{status})"].compact.join(" ")
      end

      def sepa_status_log_display
        [Settings.sepa_status[sepa_status].presence, "(#{sepa_status})"].compact.join(" ")
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
      # Accounting support
      #

      ##
      # Regular full fee in cents based on payment role.
      def regular_full_fee_cents
        get_full_regular_fee_cents(self)
      end

      ##
      # Total fee (reduced by custom fee reduction) in cents.
      def total_fee_cents
        reduction = active_fee_rule&.total_fee_reduction_cents || 0
        [get_full_regular_fee_cents(self) - reduction, 0].max
      end

      ##
      # Label for displaying total_fee_cents.
      #
      # The label gives some hints about a fee reduction if any applies.
      def total_fee_label(comment_sep: " ", space: " ")
        reduction = active_fee_rule&.total_fee_reduction_cents || 0
        if reduction != 0
          reduction_display = format_cents_de(reduction, space: "", zero_cents: "")
          comment = active_fee_rule&.total_fee_reduction_comment
          comment_sep = ERB::Util.html_escape(comment_sep)
          space = ERB::Util.html_escape(space)
          reduction_comment = "reduziert um #{reduction_display}"
          if !comment.blank?
            reduction_comment = "#{comment}: #{reduction_comment}"
          end
          reduction_comment = reduction_comment.gsub(/\s+/, space).html_safe
          "Beitrag#{comment_sep}(#{reduction_comment})".html_safe
        else
          "Beitrag".html_safe
        end
      end

      def accounting_entries
        entries = AccountingEntry.where(subject: self).includes([:author, :direct_debit_pre_notification, :camt_transaction]).to_a
        entries.sort_by! { |elt| elt.created_at }
        entries
      end

      def direct_debit_pre_notifications
        entries = WsjrdpDirectDebitPreNotification.where(subject: self).to_a
        entries.sort_by! { |elt| elt.created_at }
        entries
      end

      ##
      # amount paid in cents
      def amount_paid_cents
        accounting_entries.map { |e| e.amount_cents }.sum
      end

      ##
      # Array of all installments
      #
      # Each entry of the returned array has two elements:
      # * An array of year and month
      # * The installment amount in cents
      #
      # Examples:
      # [[[2025, 8], 340000] - YP august 2025 early payer installments
      def installments_cents
        installments = active_fee_rule&.get_installments_cents
        if !installments.nil?
          installments
        else
          regular_installments_cents_for(self).dup
        end
      end

      #
      # active fee rule
      #

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

      def deregistration_effective_date
        super&.to_date
      end

      def deregistration_effective_date=(value)
        value = value.to_date if value.respond_to?(:to_date)
        super(value&.to_fs(:iso8601))
      end

      def deregistration_contractual_compensation_cents(today: nil)
        compute_contractual_compensation_cents(total_fee_cents, today: today)
      end

      def deregistration_refund_cents(today: nil)
        compensation_cents = deregistration_actual_compensation_cents || deregistration_contractual_compensation_cents(today: today)
        [amount_paid_cents - compensation_cents, 0].max
      end

      def deregistration_open_cents(today: nil)
        compensation_cents = deregistration_actual_compensation_cents || deregistration_contractual_compensation_cents(today: today)
        [compensation_cents - amount_paid_cents, 0].max
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
          tag_name = ContractHelper::GOOD_CONDUCT_MISSING_TAG
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

      def _maybe_fetch_fee_rules
        if !@fee_rules_fetched
          active_fee_rule, planned_fee_rule = fetch_fee_rules(self)
          @active_fee_rule ||= active_fee_rule
          @planned_fee_rule ||= planned_fee_rule
          @fee_rules_fetched = true
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
