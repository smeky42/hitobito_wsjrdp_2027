# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# A DATEV personal account (Personenkonto): CREDITOR
# (Kreditor/Lieferant, 7xxxxx-9xxxxx) or DEBITOR (Debitor/Kunde,
# 1xxxxx-6xxxxx); see doc/fin/personal_accounts.md for which column
# comes from which system.
class WsjrdpPersonalAccount < ActiveRecord::Base
  STATUS_ACTIVE = "active"
  STATUS_DEACTIVATED = "deactivated"

  validates :number, presence: true, uniqueness: true

  belongs_to :represented_person, class_name: "Person", optional: true,
    inverse_of: :personal_accounts

  # Bookings whose Konto (account) is this personal account
  # rubocop:disable Rails/HasManyOrHasOneDependent -- deliberately no
  # :dependent option: bookings are independent facts; deleting an account
  # must never touch them (and there is no FK to nullify).
  has_many :bookings, class_name: "DatevBooking", as: :account,
    primary_key: :number, foreign_key: :account_number, inverse_of: :account
  # rubocop:enable Rails/HasManyOrHasOneDependent

  # Bank accounts / wallets that map to this personal account (by
  # number).  dependent: :nullify -- removing a personal account clears
  # the mapping on the fin accounts (there is no FK; the link is
  # polymorphic, by number).
  has_many :fin_accounts, class_name: "WsjrdpFinAccount",
    as: :bookkeeping_account, primary_key: :number,
    foreign_key: :bookkeeping_account_number,
    inverse_of: :bookkeeping_account, dependent: :nullify

  # moss_status is NULL for accounts without a Moss connection
  scope :active, -> { where(moss_status: STATUS_ACTIVE) }
  scope :deactivated, -> { where(moss_status: [STATUS_DEACTIVATED, nil]) }

  def active?
    moss_status == STATUS_ACTIVE
  end

  def to_s
    "#{number} #{display_short_name}"
  end
end
