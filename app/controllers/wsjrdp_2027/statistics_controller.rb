# frozen_string_literal: true

#  Copyright (c) 2025, German Contingent for the Worldscoutjamboree 2027. This file is part of
#  hitobito_wsjrdp_2027 and licensed under the Affero General Public License version 3
#  or later. See the COPYING file at the top-level directory or at
#  https://github.com/hitobito/hitobito_wsjrdp_2027.

module Wsjrdp2027::StatisticsController
  extend ActiveSupport::Concern
  included do
    include ContractHelper

    def index
      @group = Group.find(params[:group_id])
      groups = @group.self_and_descendants
      @people = Person.joins(:groups).where(groups: {id: groups.pluck(:id)}).distinct

      start_date = Date.parse("2025-05-01")
      end_date = Time.zone.today

      @people_by_registration_date = get_people_by_registration_date(@people, start_date, end_date)
      @people_by_status = get_people_by_status(@people)
      @people_by_role = get_people_by_role(@people)
      @registration_completed_people_by_role = get_registration_completed_people_by_role(@people)
      @registration_verified_people_by_role = get_registration_verified_people_by_role(@people)
    end

    private

    def get_people_by_registration_date(people, start_date, end_date)
      total_daily = {}
      role_daily_counts = Hash.new { |h, k| h[k] = {} }

      (start_date..end_date).each do |day|
        day_people = people.where(created_at: day.all_day)
        total_daily[day] = day_people.count

        day_people.each do |person|
          role = person_payment_role_full_name(PersonDecorator.new(person))
          next if role.blank?
          role_daily_counts[role][day] = role_daily_counts[role].fetch(day, 0) + 1
        end
      end

      [{name: "Gesamt", data: total_daily}] +
        role_daily_counts.map { |role, data| {name: role, data: data} }
    end

    def role_counts(people)
      counts = Hash.new(0)
      people.each do |person|
        role = person_payment_role_full_name(PersonDecorator.new(person))
        counts[role] += 1 if role.present?
      end
      counts
    end

    def get_people_by_status(people)
      people.group_by(&:status).transform_values(&:count)
    end

    def get_people_by_role(people)
      chart_data(role_counts(people))
    end

    def get_registration_completed_people_by_role(people)
      verified_statuses = ["upload", "in_review", "reviewed"]
      verified_people = people.select { |p| verified_statuses.include?(p.status) }
      chart_data(role_counts(verified_people))
    end

    def get_registration_verified_people_by_role(people)
      final_verified_people = people.select { |p| p.status == "confirmed" }
      chart_data(role_counts(final_verified_people))
    end

    def chart_data(counts)
      counts.map { |role, count| [role, count] }
    end
  end
end
