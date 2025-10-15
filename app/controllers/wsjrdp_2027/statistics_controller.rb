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
      people_relation = ::Person.joins(:groups).where(groups: {id: groups.pluck(:id)}).distinct.includes(:roles => [:group])

      @total_count = people_relation.count
      people = people_relation.to_a
      decorated = people.map { |p| PersonDecorator.new(p) }

      @ist_count = decorated.count { |d| ist?(d) }
      @yp_count = decorated.count { |d| yp?(d) }
      @ul_count = decorated.count { |d| ul?(d) }
      @cmt_count = decorated.count { |d| cmt?(d) }
    end

    def statistics_data
      groups = @group.self_and_descendants
      people_relation = ::Person.joins(:groups).where(groups: {id: groups.pluck(:id)}).distinct.includes(:roles => [:group])
      people = people_relation.to_a

      start_date = Date.parse("2025-05-01")
      end_date = Time.zone.today

      date_aggregations = get_people_by_date_aggregations(people, start_date, end_date)

      render json: {
        people_by_registration_date: date_aggregations[:registration],
        people_by_completion_date: date_aggregations[:completion],
        people_by_status: get_people_by_status(people_relation),
        people_by_role: get_people_by_role(people),
        registration_completed_people_by_role: get_registration_completed_people_by_role(people),
        registration_verified_people_by_role: get_registration_verified_people_by_role(people)
      }
    end

    private

    def get_people_by_date_aggregations(people, start_date, end_date)
      reg_total_daily = Hash.new(0)
      reg_role_daily = Hash.new { |h, k| h[k] = Hash.new(0) }

      comp_total_daily = Hash.new(0)
      comp_role_daily = Hash.new { |h, k| h[k] = Hash.new(0) }

      people.each do |person|
        # registration (created_at)
        if person.created_at
          day = person.created_at.to_date
          if (start_date..end_date).cover?(day)
            reg_total_daily[day] += 1
            role = person_payment_role_full_name(PersonDecorator.new(person))
            reg_role_daily[role][day] += 1 if role.present?
          end
        end

        # completion (complete_document_upload_at)
        if person.complete_document_upload_at
          day = person.complete_document_upload_at.to_date
          if (start_date..end_date).cover?(day)
            comp_total_daily[day] += 1
            role = person_payment_role_full_name(PersonDecorator.new(person))
            comp_role_daily[role][day] += 1 if role.present?
          end
        end
      end

      (start_date..end_date).each do |d|
        reg_total_daily[d] = 0 unless reg_total_daily.key?(d)
        comp_total_daily[d] = 0 unless comp_total_daily.key?(d)
      end

      reg_role_daily.each_value { |h| (start_date..end_date).each { |d| h[d] = 0 unless h.key?(d) } }
      comp_role_daily.each_value { |h| (start_date..end_date).each { |d| h[d] = 0 unless h.key?(d) } }

      registration = [{name: "Gesamt", data: reg_total_daily}] +
        reg_role_daily.map { |role, data| {name: role, data: data} }

      completion = [{name: "Gesamt", data: comp_total_daily}] +
        comp_role_daily.map { |role, data| {name: role, data: data} }

      {registration: registration, completion: completion}
    end

    def role_counts(people)
      counts = Hash.new(0)
      people.each do |person|
        role = person_payment_role_full_name(PersonDecorator.new(person))
        counts[role] += 1 if role.present?
      end
      counts
    end

    def get_people_by_status(people_relation)
      people_relation.group(:status).count
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
