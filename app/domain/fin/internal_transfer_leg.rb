# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# One leg of an Umbuchung as the pages show it: a bank transaction or a Moss
# transaction, read through one interface. The side follows from the sign --
# money leaving an account is the "Von" side, money arriving the "Nach" side.
class Fin::InternalTransferLeg
  SOURCES = {"camt" => "WsjrdpCamtTransaction", "moss" => "MossTransaction"}.freeze

  attr_reader :record

  # The legs behind keys like "camt:12"; an unknown source or id raises.
  def self.find_all(keys)
    Array(keys).map do |key|
      source, id = key.to_s.split(":", 2)
      new(SOURCES.fetch(source).constantize.find(Integer(id)))
    end
  end

  def self.wrap(records) = records.map { |record| new(record) }

  def initialize(record)
    @record = record
  end

  def key = record.internal_transfer_leg_key

  def source = record.internal_transfer_leg_source

  def moss? = source == "moss"

  def account = record.fin_account

  def amount = moss? ? record.signed_total_base_amount : record.signed_base_amount

  def date = moss? ? record.booking_date : record.value_date

  def text = moss? ? record.description : record.description.to_s

  # Who the money went to or came from, as the bank names them; nil for Moss,
  # whose text already names the party.
  def party
    return nil if moss?

    from? ? record.cdtr_name : record.dbtr_name
  end

  def from? = amount.negative?

  def to? = !from?

  def ==(other) = other.is_a?(self.class) && other.key == key

  alias_method :eql?, :==

  def hash = key.hash
end
