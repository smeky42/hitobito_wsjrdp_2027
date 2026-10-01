# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The Abstimmung page "Unit-Buchungen" (Fin::UnitBookingsController): every
# booking a unit sees should either count against the unit's budget on the
# unit's own cost center, or carry a secondary cost center that says where the
# cost belongs centrally -- the travel costs of a unit meeting on 3810, say.
#
# A unit sees every booking whose primary or secondary cost center is a unit's
# own (is_unit_cost_center, doc/fin/unit_budget.md). Those fall into three
# disjoint sets:
#
#   unit_budget  the booking counts against the Unit-Budget
#                (DatevBooking::EFFECTIVE_IS_UNIT_BUDGET_SQL), the way a group's
#                Buchhaltung counts it
#   assigned     it does not, and a secondary cost center is set: a central
#                booking naming the unit, or the unit's booking naming where
#                the cost belongs
#   open         it does not, the unit's own cost center, no secondary cost
#                center -- what the page lists, and what #assign! writes to
#
# Every relation is built on the account joins the Unit-Budget expression
# names (DatevBooking.with_unit_budget_accounts); a host that needs the
# resolved columns as well hands in DatevBooking.with_unit_budget.
#
# Both lists offer a quick-select over all pages by ATOM, a value every row
# carries (`selection_atom`, selected by #with_atom) and the page's selection
# posts (`select_all`). An open booking's atom is the account that keeps it
# out of the Unit-Budget -- "k66630" for the Konto, "g66680" for the
# Gegenkonto, "b" for the booking's own flag --, an assigned booking's the
# central cost center of its pair.
class Fin::UnitBookingReconciliation
  UNIT_BUDGET_SQL = DatevBooking::EFFECTIVE_IS_UNIT_BUDGET_SQL

  # The deciding side of an open booking (DatevBooking::IS_UNIT_BUDGET_SOURCE_SQL):
  # the Gegenkonto where it alone said no, the booking where its flag did,
  # else the Konto.
  OPEN_ATOM_SQL = <<~SQL.squish
    CASE (#{DatevBooking::IS_UNIT_BUDGET_SOURCE_SQL})
      WHEN 'gegenkonto' THEN 'g' || datev_bookings.offsetting_account_number
      WHEN 'booking' THEN 'b'
      ELSE 'k' || datev_bookings.account_number
    END
  SQL

  # The central cost center of an assigned booking: the secondary one of the
  # unit's own booking, the primary one of a central booking naming the unit.
  ASSIGNED_ATOM_SQL = <<~SQL.squish
    CASE WHEN datev_bookings.cost_center_number IN
              (SELECT number FROM wsjrdp_cost_centers WHERE is_unit_cost_center)
         THEN datev_bookings.secondary_cost_center_number
         ELSE datev_bookings.cost_center_number
    END
  SQL

  # The secondary cost center the page proposes for an open booking, by the
  # expense account on either side of it: the travel-cost accounts belong to
  # 3810 Unit-Treffen Reisekosten, where the Haushalt plans the travel to unit
  # meetings. A proposal naming a cost center the master data does not carry is
  # no proposal.
  PROPOSED_SECONDARY_COST_CENTERS = {
    "66630" => "3810", # Reisekosten ÖPNV
    "66631" => "3810", # Reisekosten Leihwagen
    "66680" => "3810", # Kilometergelderstattung
    "65800" => "3810"  # Mautgebühren
  }.freeze

  Figure = Data.define(:count, :sum)

  # One button of a quick-select: the atom its rows carry, what it says, how
  # many rows and their sum.
  Atom = Data.define(:key, :label, :count, :sum)

  # "3810 Unit Treffen Reisekosten": number and full name, the way the page
  # names a cost center.
  def self.label(cost_center) = "#{cost_center.number} #{cost_center.name}".strip

  # The cost-center numbers of every unit's own cost center.
  def unit_numbers
    @unit_numbers ||= WsjrdpCostCenter.where(is_unit_cost_center: true).order(:number).pluck(:number)
  end

  # What the units see: primary OR secondary cost center a unit's own.
  def shown(base = joined)
    base.where(cost_center_number: unit_numbers)
      .or(base.where(secondary_cost_center_number: unit_numbers))
  end

  def unit_budget(base = joined)
    shown(base).where(UNIT_BUDGET_SQL)
  end

  def assigned(base = joined)
    shown(base).where.not(secondary_cost_center_number: nil).where("NOT (#{UNIT_BUDGET_SQL})")
  end

  def open(base = joined)
    base.where(cost_center_number: unit_numbers, secondary_cost_center_number: nil)
      .where("NOT (#{UNIT_BUDGET_SQL})")
  end

  # The relation with its rows' atom as the column `selection_atom`.
  def with_atom(relation, atom_sql) = relation.select("(#{atom_sql}) AS selection_atom")

  # The rows of `relation` whose atom is one of `atoms`.
  def with_atoms(relation, atom_sql, atoms) = relation.where("(#{atom_sql}) IN (?)", Array(atoms))

  # Count and signed sum of a relation.
  def figure(relation)
    Figure.new(count: relation.count(:all), sum: relation.sum(:signed_base_amount) || 0)
  end

  # The quick-select of the open bookings: one Atom per deciding account, most
  # rows first.
  def open_atoms(relation = open)
    atoms(relation, OPEN_ATOM_SQL) do |keys|
      names = account_names(keys.map { |key| key.slice(1..) })
      keys.to_h { |key| [key, open_atom_label(key, names)] }
    end
  end

  # The quick-select of the assigned bookings: one Atom per central cost
  # center, most rows first.
  def assigned_atoms(relation = assigned)
    atoms(relation, ASSIGNED_ATOM_SQL) do |keys|
      names = WsjrdpCostCenter.where(number: keys).pluck(:number, :name).to_h
      keys.to_h { |key| [key, [key, names[key]].compact.join(" ")] }
    end
  end

  # The proposed secondary cost center of a booking: by its Konto, else by its
  # Gegenkonto (a refund paid from the bank account has the travel-cost account
  # there); nil without one.
  def proposal(booking)
    proposal_for(booking.account_number) || proposal_for(booking.offsetting_account_number)
  end

  def proposal_for(account_number)
    proposal_cost_centers[PROPOSED_SECONDARY_COST_CENTERS[account_number.to_s]]
  end

  # What a secondary cost center may be set to: every cost center that is not a
  # unit's own, the placeholder number the Kostenstellen list pins out
  # excluded.
  def assignable_cost_centers
    @assignable_cost_centers ||= WsjrdpCostCenter.where(is_unit_cost_center: [false, nil])
      .where.not(number: Fin::CostCentersController::HIDDEN_COST_CENTER_NUMBER).order(:number).to_a
  end

  # Sets the secondary cost center of the OPEN bookings among `ids` -- an id
  # of any other booking is ignored -- and answers how many changed. A number
  # that names no assignable cost center raises.
  def assign!(ids, cost_center_number)
    target = assignable_cost_centers.find { |cost_center| cost_center.number == cost_center_number.to_s }
    raise ArgumentError, "#{cost_center_number.inspect} ist keine zuweisbare Kostenstelle" unless target

    update(open.where(id: Array(ids)), secondary_cost_center_number: target.number)
  end

  # Takes the secondary cost center off the ASSIGNED bookings among `ids` --
  # an id of any other booking is ignored -- and answers how many changed.
  def clear!(ids)
    update(assigned.where(id: Array(ids)), secondary_cost_center_number: nil)
  end

  private

  def joined = DatevBooking.with_unit_budget_accounts

  def update(relation, attributes)
    ids = relation.pluck(:id)
    return 0 if ids.empty?

    DatevBooking.where(id: ids).update_all(attributes.merge(updated_at: Time.zone.now))
  end

  # The atoms of a relation, most rows first; the block turns the keys into
  # {key => label} in one go.
  def atoms(relation, atom_sql)
    rows = relation.unscope(:select).group(Arel.sql(atom_sql)).pluck(
      Arel.sql(atom_sql), Arel.sql("COUNT(*)"), Arel.sql("SUM(datev_bookings.signed_base_amount)")
    )
    labels = yield(rows.map { |key, _count, _sum| key.to_s })
    rows.sort_by { |key, count, _sum| [-count, key.to_s] }.map do |key, count, sum|
      Atom.new(key: key.to_s, label: labels.fetch(key.to_s), count: count, sum: sum || 0)
    end
  end

  def open_atom_label(key, names)
    number = key[1..]
    case key[0]
    when "g" then "Gegenkto #{[number, names[number]].compact.join(" ")}"
    when "b" then "Buchung (Flag nein)"
    else "Konto #{[number, names[number]].compact.join(" ")}"
    end
  end

  # number => short name of the accounts the open atoms name, Sachkonten and
  # Kreditoren alike.
  def account_names(numbers)
    WsjrdpLedgerAccount.where(number: numbers).pluck(:number, :display_short_name).to_h
      .merge(WsjrdpPersonalAccount.where(number: numbers).pluck(:number, :display_short_name).to_h)
  end

  def proposal_cost_centers
    @proposal_cost_centers ||= WsjrdpCostCenter
      .where(number: PROPOSED_SECONDARY_COST_CENTERS.values.uniq).index_by(&:number)
  end
end
