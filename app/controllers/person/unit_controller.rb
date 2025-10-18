# frozen_string_literal: true

class Person::UnitController < ApplicationController
  include ContractHelper

  before_action :authorize_action

  decorates :group, :person

  respond_to :html

  def show
    @person ||= person
    @group ||= group
    authorize!(:log, current_user)

    @people_in_cluster ||= people_in_cluster
    @common_ul_unit_code ||= common_ul_unit_code

    render "show"
  end

  def fill_cluster_code
    @person ||= person
    @group ||= group
    authorize!(:log, current_user)

    @people_in_cluster ||= people_in_cluster
    @common_ul_unit_code ||= common_ul_unit_code

    if @common_ul_unit_code
      @people_in_cluster.each do |p|
        p.cluster_code = @common_ul_unit_code
        p.save
      end
    end
    redirect_back_or_to(unit_group_person_path)
  end

  def clear_cluster_code
    @person ||= person
    @group ||= group
    authorize!(:log, current_user)

    @people_in_cluster ||= people_in_cluster

    Person.transaction do
      @people_in_cluster.each do |p|
        p.cluster_code = nil
        p.save
      end
    end
    redirect_back_or_to(unit_group_person_path)
  end

  private

  def authorize_action
    authorize!(:edit, person)
  end

  def person
    @person ||= fetch_person
  end

  def group
    @group ||= Group.find(params[:group_id])
  end

  def common_ul_unit_code
    ul_unit_code_set = Set.new(ul_in_cluster.map { |p| normalized_unit_code_or_nil(p.unit_code) }.select { |uc| uc })
    if ul_unit_code_set.size == 1
      ul_unit_code_set.to_a[0]
    end
  end

  def ul_in_cluster
    fetch_people_in_cluster unless @ul_in_cluster
    @ul_in_cluster
  end

  def yp_in_cluster
    fetch_people_in_cluster unless @yp_in_cluster
    @yp_in_cluster
  end

  def people_in_cluster
    fetch_people_in_cluster unless @people_in_cluster
    @people_in_cluster
  end

  def fetch_people_in_cluster
    all_p = Person.find_by_sql(
      [
        %q(
WITH RECURSIVE buddy_cluster ("id", "buddy_id", "buddy_id_ul", "buddy_id_yp", "rdp_assoc", "ids") AS (
  SELECT
    p."id",
    CONCAT(p.buddy_id, '-', p."id"::CHARACTER VARYING),
    p.buddy_id_ul,
    p.buddy_id_yp,
    CONCAT(p.rdp_association, '<>', p.rdp_association_region, '<>', p.rdp_association_sub_region, '<>', p.rdp_association_group),
    ARRAY[p."id"]
  FROM "people" p WHERE p."id" = ?
  UNION
  SELECT
    p."id",
    CONCAT(p.buddy_id, '-', p."id"::CHARACTER VARYING),
    p.buddy_id_ul,
    p.buddy_id_yp,
    CONCAT(p.rdp_association, '<>', p.rdp_association_region, '<>', p.rdp_association_sub_region, '<>', p.rdp_association_group),
    ids || p."id"
  FROM "people" p
  INNER JOIN buddy_cluster c ON
    p.buddy_id_ul = c.buddy_id
    OR p.buddy_id_yp = c.buddy_id
    OR CONCAT(COALESCE(p.buddy_id, 'none'), '-', p."id"::CHARACTER VARYING) in (c.buddy_id_ul, c.buddy_id_yp)
  WHERE NOT (p."id" = ANY(c.ids))
)
SELECT TRUE AS "in_cluster", p.* FROM people p
WHERE
      p.id IN (SELECT DISTINCT "id" FROM buddy_cluster)
  AND p.status NOT IN ('deregistration_noted', 'deregistered')
UNION
SELECT FALSE AS "in_cluster", p.* FROM people p
WHERE
      CONCAT(p.rdp_association, '<>', p.rdp_association_region, '<>', p.rdp_association_sub_region, '<>', p.rdp_association_group) IN (SELECT DISTINCT rdp_assoc FROM buddy_cluster)
  AND p.id NOT IN (SELECT DISTINCT "id" FROM buddy_cluster)
  AND p.status NOT IN ('deregistration_noted', 'deregistered')
ORDER BY first_name, last_name
        ),
        person.id
      ]
    )
    p_in_cluster = all_p.select { |p| p.in_cluster }
    @ul_in_cluster = p_in_cluster.select { |p| ul?(p) }
    @yp_in_cluster = p_in_cluster.select { |p| yp?(p) }
    @people_in_cluster = @ul_in_cluster + @yp_in_cluster
    p_not_in_cluster = all_p.select { |p| !p.in_cluster }
    @ul_not_in_cluster = p_not_in_cluster.select { |p| ul?(p) }
    @yp_not_in_cluster = p_not_in_cluster.select { |p| yp?(p) }
    @ist_not_in_cluster = p_not_in_cluster.select { |p| ist?(p) }
    @cmt_not_in_cluster = p_not_in_cluster.select { |p| cmt?(p) }
    @ulyp_not_in_cluster = @ul_not_in_cluster + @yp_not_in_cluster
    nil
  end
end
