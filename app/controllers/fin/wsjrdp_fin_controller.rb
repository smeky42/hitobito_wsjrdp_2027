# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class Fin::WsjrdpFinController < ApplicationController
  include ContractHelper

  before_action :authorize_action

  helper_method :confirmed_people_sepa_status_not_ok
  helper_method :not_confirmed_people_in_confirmed_groups
  helper_method :other_people_with_nonzero_paid

  CONFIRMED_OR_DEREGISTERED_STATUS = ["confirmed", "deregistration_noted", "deregistered"]
  UNCONFIRMED_GROUPS = [5, 6, 7, 45, 46]

  def index
    @wsjrdp_fin_accounts = WsjrdpFinAccount.all
  end

  private

  def authorize_action
    authorize!(:fin_admin, WsjrdpFinAccount)
  end

  def confirmed_people_sepa_status_not_ok
    return @confirmed_people_sepa_status_not_ok if @confirmed_people_sepa_status_not_ok.present?
    @confirmed_people_sepa_status_not_ok = Person
      .where(status: "confirmed")
      .where.not(sepa_status: "ok")
      .to_a
    people_sort!(@confirmed_people_sepa_status_not_ok)
  end

  def not_confirmed_people_in_confirmed_groups
    return @not_confirmed_people_in_confirmed_groups if @not_confirmed_people_in_confirmed_groups.present?
    @not_confirmed_people_in_confirmed_groups = Person
      .where.not(status: "confirmed")
      .where.not(primary_group_id: UNCONFIRMED_GROUPS)
      .to_a
    people_sort!(@not_confirmed_people_in_confirmed_groups)
  end

  def other_people_with_nonzero_paid
    return @other_people_with_nonzero_paid if @other_people_with_nonzero_paid.present?
    sum_expr = "SUM(COALESCE(accounting_entries.amount_cents, 0))"
    @other_people_with_nonzero_paid = Person
      .left_outer_joins(:accounting_entries)
      .select("people.*, #{sum_expr} AS accounting_entries_sum")
      .having("#{sum_expr} <> 0")
      .where(primary_group_id: UNCONFIRMED_GROUPS)
      .group("people.id")
      .to_a
    people_sort!(@other_people_with_nonzero_paid)
  end

  def people_sort!(people)
    people.sort_by! { |p| [short_wsj_role(p), p.id] }
    people
  end
end
