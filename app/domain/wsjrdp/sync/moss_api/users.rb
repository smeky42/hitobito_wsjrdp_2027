# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027
module Wsjrdp::Sync::MossApi
  # The users (GET /v1/users) into moss_users. An empty person is filled
  # with the one person whose moss_email is the user's e-mail (ignoring
  # case); a person set in Hitobito stays. The person with that moss_email
  # gets moss_status, moss_team and moss_roles, with a PaperTrail version.
  # The phone comes from the CSV export only.
  class Users < ListPart
    self.key = "moss_api.organisation_structure.users"
    self.depends_on = [Teams.key]
    self.path = "v1/users"
    self.model = MossUser
    self.uuid_column = "moss_user_uuid"
    self.notice_fields = {"unknown_team" => "moss_team_uuid", "unknown_manager" => "manager_uuid",
                          "without_person" => "person_id", "without_person_deactivated" => "person_id",
                          "ambiguous_person" => "person_id", "moss_user_without_contract" => "person_id"}.freeze
    # A person without a contract has no Moss user as a rule, nor has one who
    # left without a contract running: for them, no user is no news.
    NO_USER_EXPECTED = ->(status, contract) { contract == "none" || (status == "deregistered" && contract == "ended") }

    private

    def attributes(record)
      {moss_user_uuid: record["id"], moss_organisation_uuid: record["organisationId"],
       moss_team_uuid: record["teamId"], manager_uuid: record["managerId"], email: record["email"],
       first_name: record["firstName"], last_name: record["lastName"], status: record["status"],
       roles: roles(record), moss_created_at: instant(record["createTime"]),
       moss_updated_at: instant(record["updateTime"]), person_id: person_id(record)}
    end

    def label(record)
      [record["first_name"], record["last_name"]].compact_blank.join(" ").presence || record["email"].presence ||
        record["moss_user_uuid"]
    end

    # The name, the status and the Moss e-mail.
    def item_label(record)
      name = [record["firstName"], record["lastName"]].compact_blank.join(" ").presence || record["email"].presence
      [name || record["id"], ("Status: #{record["status"]}" if record["status"].present?),
        ("E-Mail: #{record["email"]}" if record["email"].present? && record["email"] != name)].compact.join(" · ")
    end

    # Sorted: Moss's order carries no meaning and may change.
    def roles(record) = Array(record["roles"]).sort

    def instant(text) = text.presence && Wsjrdp::InstantInput.parse(text)

    def person_id(record) = current_people[record["id"].to_s.downcase] || match(record)

    # The one person with the user's Moss e-mail, or nil.
    def match(record) = matches(record).then { |matches| matches.first if matches.one? }

    def matches(record) = people_by_email[record["email"].to_s.downcase] || []

    # {lower-case Moss e-mail => [person id, …]}
    def people_by_email
      @people_by_email ||= Person.where("additional_info->>'moss_email' <> ''")
        .pluck(Arel.sql("LOWER(additional_info->>'moss_email')"), :id)
        .group_by(&:first).transform_values { |pairs| pairs.map(&:last) }
    end

    def current_people = @current_people ||= MossUser.pluck(:moss_user_uuid, :person_id).to_h

    # One change per person whose fields differ; values {field => [old, new]},
    # ref the Moss user they come from.
    def person_changes(records)
      targets = records.filter_map { |record| (id = match(record)) && [id, [person_fields(record), record["id"]]] }.to_h
      people = Person.where(id: targets.keys).pluck(:id, :first_name, :last_name, :additional_info)
      people.filter_map do |id, first_name, last_name, info|
        fields, uuid = targets[id]
        diff = fields.filter_map { |field, value| [field, [info[field], value]] unless same?(info[field], value) }.to_h
        next if diff.empty?

        Wsjrdp::Sync::Plan::Change.new(action: "update", key: "#{PERSON_KEY}#{id}",
          label: [first_name, last_name].compact_blank.join(" ").presence || "##{id}", values: diff,
          target: "Person", target_column: "additional_info", ref: uuid)
      end
    end

    # Roles in another order are the same roles.
    def same?(old, new) = (old.is_a?(Array) && new.is_a?(Array)) ? old.sort == new : old == new

    def person_fields(record)
      {"moss_status" => record["status"].presence, "moss_team" => team_names[record["teamId"]],
       "moss_roles" => roles(record).presence}
    end

    # {team UUID => name}: what this run fetched, else the table.
    def team_names
      @team_names ||= context.data_of(Teams.key)&.dig(Teams.data_name)&.to_h { |team| [team["id"], team["name"].presence] } ||
        MossTeam.in_moss.pluck(:moss_team_uuid, :name).to_h
    end

    # One statement for all people, one insert for their versions.
    def apply_person_changes(changes)
      return 0 if changes.empty?

      rows = changes.map do |change|
        id = Integer(change.key.delete_prefix(PERSON_KEY))
        set = change.values.transform_values(&:last).compact
        [id, set, change.values.keys - set.keys, change.values]
      end
      values = rows.map { |id, set, unset, _| "(#{id}, #{quote(set.to_json)}::jsonb, #{quote_array(unset)})" }
      written = Person.connection.update(<<~SQL.squish)
        UPDATE people SET additional_info = (people.additional_info - v.unset) || v.set, updated_at = #{quote(context.now)}
        FROM (VALUES #{values.join(", ")}) AS v(id, set, unset) WHERE people.id = v.id
      SQL
      PaperTrail::Version.insert_all!(rows.map { |id, _, _, values| version(id, values) })
      written
    end

    def version(id, values)
      {item_type: "Person", item_id: id, main_type: "Person", main_id: id, event: "update",
       whodunnit: context.actor&.id&.to_s, whodunnit_type: "Person", created_at: context.now,
       object_changes: YAML.dump(values)}
    end

    def quote(value) = Person.connection.quote(value)

    def quote_array(values) = "ARRAY[#{values.map { |value| quote(value) }.join(", ")}]::text[]"

    def notices(records, changes, table)
      teams = known(MossTeam, :moss_team_uuid, Teams.key, Teams.data_name)
      managers = Set.new(records.pluck("id"))
      without_person = records.select { |record| person_id(record).nil? }
      ambiguous = without_person.select { |record| matches(record).size > 1 }
      deactivated, active = without_person.partition { |record| record["status"] == MossUser::STATUS_DEACTIVATED }
      (super + [warning("ambiguous_person", items(ambiguous)),
        important("unknown_team", dangling(records, "teamId", teams)),
        important("unknown_manager", dangling(records, "managerId", managers)),
        important("without_person", items(active)),
        hint("without_person_deactivated", items(deactivated)),
        important("moss_user_without_contract", users_without_contract(records))] +
        people_without_user_notices(records)).reject { |notice| notice.keys.empty? }
    end

    # Users whose person has no contract: {uuid => "… → Person: Name"}.
    def users_without_contract(records)
      linked = records.filter_map { |record| (id = person_id(record)) && [record, id] }
      people = Person.where(id: linked.map(&:last), contract_status: "none").index_by(&:id)
      linked.select { |_, id| people.key?(id) }
        .to_h { |record, id| [record["id"], "#{item_label(record)} → Person: #{people[id].full_name}"] }
    end

    # People whose Moss e-mail is no user's: important, unless no user is
    # what to expect of them (NO_USER_EXPECTED), then a hint. Each also says
    # whether a user of the same name exists, in case the e-mail is wrong.
    def people_without_user_notices(records)
      emails = records.to_set { |record| record["email"].to_s.downcase }
      ids = people_by_email.except(*emails).values.flatten
      people = Person.where(id: ids).order(:last_name, :first_name).to_a
      expected, other = people.partition { |person| NO_USER_EXPECTED.call(person.status, person.contract_status) }
      by_name = records.group_by { |record| name_key(record["firstName"], record["lastName"]) }
      [important("person_without_moss_user", person_items(other, by_name)),
        hint("person_without_moss_user_expected", person_items(expected, by_name))]
    end

    # {"person:<id>" => "Name · Status: … · Vertrag: … · Rolle: … · Moss-E-Mail: … · <name search>"}
    def person_items(people, by_name)
      people.to_h do |person|
        name = [person.first_name, person.last_name].compact_blank.join(" ")
        role = person.wsjrdp_role
        facts = [name.presence || "##{person.id}", "Status: #{person.status}", "Vertrag: #{person.contract_status}",
          ("Rolle: #{role}" if role.present?), "Moss-E-Mail: #{person.moss_email}",
          same_name(name, by_name[name_key(person.first_name, person.last_name)])]
        ["#{PERSON_KEY}#{person.id}", facts.compact.join(" · ")]
      end
    end

    # What the search by first and last name found.
    def same_name(name, users)
      return "kein Moss-Benutzer namens #{name}" if users.blank?

      "Moss-Benutzer gleichen Namens: " + users.map { |user| "#{user["email"]} (#{user["status"]})" }.join(", ")
    end

    def name_key(first_name, last_name) = [first_name, last_name].map { |part| part.to_s.squish.downcase }
  end
end
