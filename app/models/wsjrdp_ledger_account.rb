# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# A ledger account (Sachkonto): a unique account number and its
# (optional) name.  Note: `name` may be nil for accounts that have no
# name in the DATEV chart export.
#
# 6-digit personal accounts (Debitoren 1xxxxx-6xxxxx, Kreditoren
# 7xxxxx-9xxxxx) are NOT stored here -- they live in
# wsjrdp_personal_accounts (enforced by the
# chk_ledger_account_number_not_personal_account CHECK constraint,
# `number !~ '^[1-9]\d{5}$'`).
class WsjrdpLedgerAccount < ActiveRecord::Base
  STATUS_ACTIVE = "active"
  STATUS_DEACTIVATED = "deactivated"

  validates :number, presence: true, uniqueness: true

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
