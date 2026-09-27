# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027
  # The scopes of an API key (service_tokens.scopes, Wsjrdp2027::ServiceToken).
  #
  # Every area has one base scope and any number of extras, each a full name
  # of the form "<area>" or "<area>:<level>":
  #
  #   area                  base            extras
  #   people                people          people:log
  #   groups                groups          groups:log
  #   events                events          events:log
  #   invoices              invoices        -
  #   event_participations  event_participations  -
  #   mailing_lists         mailing_lists   -
  #   finance               finance:read    finance:audit finance:write finance:manage
  #
  # The bases of the core areas are the core's boolean columns of the same
  # name (and the names of the core's OAuth scopes). The bases work on their
  # own; the extras need an acting person and set their base with them.
  module ServiceTokenScopes
    CORE_AREAS = %w[people groups events invoices event_participations mailing_lists].freeze

    # area => [base, extras]
    AREAS = {
      "people" => ["people", %w[people:log]],
      "groups" => ["groups", %w[groups:log]],
      "events" => ["events", %w[events:log]],
      "invoices" => ["invoices", []],
      "event_participations" => ["event_participations", []],
      "mailing_lists" => ["mailing_lists", []],
      "finance" => ["finance:read", %w[finance:audit finance:write finance:manage]]
    }.freeze

    BASES = AREAS.values.map(&:first).freeze
    EXTRAS = AREAS.values.flat_map(&:last).freeze
    # In catalogue order: per area its base, then its extras.
    ALL = AREAS.values.flat_map { |base, extras| [base, *extras] }.freeze

    # The finance scopes and the permission each gives (doc/roles.md,
    # "Finance tiers"); several may be held, like a role holds several.
    FINANCE_PERMISSIONS = {
      "finance:read" => :finance_read,
      "finance:audit" => :finance_audit,
      "finance:write" => :finance,
      "finance:manage" => :finance_manage
    }.freeze

    module_function

    def area_of(scope) = scope.to_s.split(":").first

    def base_of(scope) = AREAS.fetch(area_of(scope)).first

    def extra?(scope) = EXTRAS.include?(scope.to_s)

    def finance?(scope) = area_of(scope) == "finance"

    def known?(scope) = ALL.include?(scope.to_s)

    # The extra :log scope of a core area, nil for an area without one.
    def log_scope(area) = AREAS.fetch(area.to_s).last.find { |scope| scope.end_with?(":log") }

    # Known scopes in catalogue order, each once.
    def ordered(scopes)
      list = Array(scopes).map(&:to_s)
      ALL.select { |scope| list.include?(scope) }
    end
  end
end
