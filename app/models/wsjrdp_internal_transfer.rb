# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# A transfer between the contingent's own accounts (Umbuchung): money that only
# moves from one of them to another and is neither income nor expense.
#
# The row stands for the transfer as a whole; its LEGS point at it through
# `internal_transfer_id`: a bank transaction, or a Moss transaction (L1, because
# a transfer moves the whole payment, not its splits). That foreign key is also
# the marker, so `internal_transfer_id IS NULL` selects the real movements
# (`.without_internal_transfer` on both leg models). A leg's side follows from
# its sign: money leaving an account is "Von", money arriving "Nach"
# (Fin::InternalTransferLeg).
#
# A transfer may be open: its other leg is not imported yet. It is deliberately
# not validated as balanced; #complete? reports the state instead.
#
# link_meta records how the legs came together: the "source" (suggestion,
# api, manual), the rule that proposed them, who linked them and when, and an
# "edits" list of every later change of the legs. See doc/fin/internal_transfers.md.
class WsjrdpInternalTransfer < ActiveRecord::Base
  # A leg asked for is already part of another transfer (or gone).
  class LegTaken < StandardError; end

  has_many :camt_transactions,
    foreign_key: :internal_transfer_id,
    inverse_of: :internal_transfer,
    class_name: "WsjrdpCamtTransaction",
    dependent: :nullify

  has_many :moss_transactions,
    foreign_key: :internal_transfer_id,
    inverse_of: :internal_transfer,
    class_name: "MossTransaction",
    dependent: :nullify

  # A new transfer of `records` (bank and Moss transactions), all of them still
  # free; raises LegTaken -- and creates nothing -- when one is not.
  def self.link!(records, meta: {}, comment: "")
    transaction do
      transfer = create!(link_meta: meta.merge("at" => Time.current.iso8601), comment: comment.to_s)
      transfer.attach!(records)
      transfer
    end
  end

  # The legs that count. A bank transaction replaced by a later statement's copy
  # or deleted is no leg any more, even if it still names this transfer.
  def legs
    camt_transactions.current.to_a + moss_transactions.to_a
  end

  # The legs as the pages read them, oldest first.
  def transfer_legs
    @transfer_legs ||= Fin::InternalTransferLeg.wrap(legs).sort_by { |leg| [leg.date || Date.new(0), leg.key] }
  end

  def from_legs = transfer_legs.select(&:from?)

  def to_legs = transfer_legs.select(&:to?)

  # The signed EUR sum of the legs, 0 once every leg is there.
  def balance
    camt_transactions.current.sum(:signed_base_amount) + moss_transactions.sum(:signed_total_base_amount)
  end

  # Money left at least one account and arrived at at least one other, and the
  # two agree to the cent.
  def complete?
    from_legs.any? && to_legs.any? && balance.zero?
  end

  def status = complete? ? :complete : :open

  # The amount moved: what arrived, or what left while nothing has arrived yet.
  def amount
    arrived = to_legs.sum(&:amount)
    arrived.zero? ? -from_legs.sum(&:amount) : arrived
  end

  # The day the transfer started: its earliest leg.
  def date = transfer_legs.filter_map(&:date).min

  def from_accounts = from_legs.map(&:account).compact.uniq

  def to_accounts = to_legs.map(&:account).compact.uniq

  # Makes `records` legs of this transfer. Only free rows are taken -- a bank
  # transaction also only while it is current --, so two people (or a person
  # and the import API) cannot link one row twice; LegTaken otherwise.
  def attach!(records)
    records.group_by(&:class).each do |klass, rows|
      scope = klass.where(id: rows.map(&:id), internal_transfer_id: nil)
      scope = scope.current if klass == WsjrdpCamtTransaction
      raise LegTaken, rows.map(&:internal_transfer_leg_key).join(", ") if scope.update_all(internal_transfer_id: id) != rows.size
    end
    reset_legs
  end

  # Releases `records` from this transfer; the rows themselves stay as they are.
  def detach!(records)
    records.group_by(&:class).each do |klass, rows|
      klass.where(id: rows.map(&:id), internal_transfer_id: id).update_all(internal_transfer_id: nil)
    end
    reset_legs
  end

  # One edit of the edit mode: the comment, legs added and legs removed, in one
  # transaction, recorded in link_meta's "edits". A transfer left without legs
  # is dissolved. Returns self (destroyed? when dissolved).
  def change!(comment:, add: [], remove: [], by: nil)
    transaction do
      detach!(remove)
      attach!(add)
      self.comment = comment.to_s unless comment.nil?
      if add.any? || remove.any?
        edit = {"at" => Time.current.iso8601, "by" => by, "added" => add.map(&:internal_transfer_leg_key),
                "removed" => remove.map(&:internal_transfer_leg_key)}
        self.link_meta = link_meta.merge("edits" => Array(link_meta["edits"]) + [edit])
      end
      save!
      destroy! if legs.empty?
    end
    self
  end

  def to_s = "Umbuchung #{id}"

  private

  def reset_legs
    @transfer_legs = nil
    camt_transactions.reset
    moss_transactions.reset
  end
end
