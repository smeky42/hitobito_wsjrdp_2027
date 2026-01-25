# frozen_string_literal: true

class AccountingEntry < ActiveRecord::Base
  include ActionView::Helpers::TextHelper
  include WsjrdpNumberHelper

  belongs_to :subject, polymorphic: true, optional: true
  belongs_to :author, polymorphic: true

  belongs_to :direct_debit_payment_info, optional: true, class_name: "WsjrdpDirectDebitPaymentInfo"
  belongs_to :direct_debit_pre_notification, optional: true, class_name: "WsjrdpDirectDebitPreNotification"
  belongs_to :payment_initiation, optional: true, class_name: "WsjrdpPaymentInitiation"
  belongs_to :camt_transaction, optional: true, class_name: "WsjrdpCamtTransaction"

  belongs_to :reversed_by, inverse_of: "reverses", optional: true, class_name: "AccountingEntry"
  belongs_to :reverses, inverse_of: "reversed_by", optional: true, class_name: "AccountingEntry"

  has_many :notes, dependent: :destroy, as: :subject, class_name: "WsjrdpNote"

  validates :subject_id, presence: true
  validates :amount_eur, presence: true
  validates :description, presence: true

  around_save :around_save_callback
  before_destroy :_before_destroy_callback

  eur_attribute :amount_eur, cents_attr: :amount_cents
  eur_attribute :pre_notified_amount_eur, cents_attr: :pre_notified_amount_cents

  def person
    @person ||= ((subject_type == "Person") ? subject : Person.root)
  end

  def group
    @group ||= (person.primary_group_id.nil? ? Group.find(person.default_group_id) : person.primary_group)
  end

  def to_s
    d = value_date || created_at.to_date
    "#{id} #{truncate(description, length: 60)} (#{amount_eur_display}) #{d}"
  end

  def link_name(length: 80)
    "#{id} #{truncate(description, length: length)} (#{amount_eur_display})"
  end

  def new_sepa_status_display
    Settings.sepa_status[new_sepa_status]
  end

  def short_dbtr
    s = [dbtr_name, dbtr_address, dbtr_iban].select { |e| !e.blank? }.join(", ")
    s.presence
  end

  def author_full_name
    if author_id.blank? || author_type != "Person" || author_id < 2
      nil
    else
      fall_back = "Unbekannte Person (id #{author_id})"
      begin
        if author.blank?
          fall_back
        else
          author.full_name
        end
      rescue
        fall_back
      end
    end
  rescue
    nil
  end

  ##
  # Return false
  #
  # Exists to have a common interface with WsjrdpDirectDebitPreNotification
  def try_skip?
    false
  end

  def pre_booked?
    false
  end

  def skipped?
    false
  end

  private

  def around_save_callback
    if amount_cents.nil?
      self.amount_cents = 0
    end
    if created_at.nil?
      self.created_at = Time.now.getlocal
    end
    if updated_at.nil?
      self.updated_at = created_at
    end
    if value_date.nil?
      self.value_date = created_at.getlocal("+02:00").to_date
    end
    if booking_date.nil?
      self.booking_date = created_at.getlocal("+02:00").to_date
    end
    if endtoend_id.blank?
      self.endtoend_id = nil
    end
    yield
  end

  def _before_destroy_callback
    if reversed_by_id.present?
      ae = AccountingEntry.find_by(id: reversed_by_id)
      if ae.present?
        ae.reverses_id = nil
        ae.save!
      end
    end
  end
end
