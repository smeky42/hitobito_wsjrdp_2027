# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# A payment reference ready for or given to a payment, made ahead by a script
# (wsjrdp_scripts: docs/payment_code.md) or by the wagon. payment_code is what
# the remittance information carries; for the type rf (an ISO 11649 creditor
# reference) it is RF, two check digits and the codeword. The row keeps the
# codeword scheme and the Reed-Solomon parameters the codeword was made with.
#
# A reference is available until it is assigned; a void one is never handed
# out. Payment notices refer to it by payment_reference_id, and the
# reference refers to nothing.
#
# The stock of available references is kept at POOL_SIZE; below LOW_STOCK it
# is worth filling up (wsjrdp_scripts or the Verwaltung page). When the stock
# is empty, assign! makes a reference itself. A reference, once assigned,
# stays assigned, whatever becomes of its notices.
class WsjrdpPaymentReference < ActiveRecord::Base
  PAYMENT_CODE_TYPES = %w[rf].freeze
  STATUSES = %w[available assigned void].freeze
  ORIGINS = %w[script wagon].freeze

  POOL_SIZE = 500
  LOW_STOCK = 100
  # A new code that collides with one made at the same moment is drawn again.
  MAX_CREATE_ATTEMPTS = 3
  # The transaction-level advisory lock every maker of codes takes before it
  # reads the codewords there are (pg_advisory_xact_lock): two makers never
  # draw against the same state, so the distances between codes hold.
  # Reading, the Verwaltung page and handing out stocked codes take no lock.
  # wsjrdp_scripts uses the same key.
  GENERATION_LOCK_KEY = 2_027_000_001

  has_many :payment_notices, class_name: "WsjrdpPaymentNotice", foreign_key: :payment_reference_id,
    inverse_of: :payment_reference, dependent: :restrict_with_error

  scope :available, -> { where(status: "available") }
  scope :assigned, -> { where(status: "assigned") }

  # As the check constraint of the table.
  validate :rf_form, if: -> { payment_code_type == "rf" }

  class << self
    # Hands out an available reference -- the oldest one nobody else is
    # taking at the moment -- or, with none left, a new one made here. Run it
    # in the transaction that saves the notice, so a failed save hands nothing
    # out.
    def assign!
      transaction do
        reference = available.order(:id).lock("FOR UPDATE SKIP LOCKED").first
        reference ||= create_generated!(status: "assigned")
        reference.update!(status: "assigned", assigned_at: Time.current) unless reference.status == "assigned"
        reference
      end
    end

    # Makes count new available references, each far enough from every
    # codeword there is, the ones made here included.
    def generate!(count)
      with_generation_lock do
        issued = Wsjrdp2027::PaymentCode::Index.new(pluck(:codeword))
        Array.new(count) do
          create_generated!(status: "available", issued: issued).tap { |reference| issued << reference.codeword }
        end
      end
    end

    # Runs the block in a transaction holding GENERATION_LOCK_KEY; the lock
    # ends with the outermost transaction.
    def with_generation_lock
      transaction do
        connection.execute("SELECT pg_advisory_xact_lock(#{GENERATION_LOCK_KEY})")
        yield
      end
    end

    # How many to make so that POOL_SIZE are available.
    def missing_for_pool = [POOL_SIZE - available.count, 0].max

    def low_stock? = available.count < LOW_STOCK

    # A new reference made here (origin wagon), its codeword far enough from
    # issued (all codewords there are, where not given), under the generation
    # lock. A collision with a code made outside the lock (a hand-written
    # insert) rolls back only this insert and draws again.
    def create_generated!(status:, issued: nil)
      with_generation_lock do
        attempts = 0
        begin
          attempts += 1
          codeword = Wsjrdp2027::PaymentCode.generate_distinct_codeword(issued || pluck(:codeword))
          transaction(requires_new: true) do
            create!(payment_code: Wsjrdp2027::PaymentCode.code_from_codeword(codeword), codeword: codeword,
              status: status, origin: "wagon", assigned_at: (status == "assigned") ? Time.current : nil)
          end
        rescue ActiveRecord::RecordNotUnique
          raise if attempts >= MAX_CREATE_ATTEMPTS

          issued = nil
          retry
        end
      end
    end
  end

  # The printed form, in groups of four.
  def printed_code = Wsjrdp2027::PaymentCode.format_code(payment_code)

  private

  def rf_form
    return if payment_code.to_s.match?(/\ARF\d{2}/) && payment_code.to_s[4..] == codeword

    errors.add(:payment_code, :invalid)
  end
end
