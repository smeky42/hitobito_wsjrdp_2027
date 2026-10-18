# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# group_person_path and group_person_url (/groups/:group_id/people/:id) for
# the person's primary group answer the person's page without a group,
# /people/:id (person_path, rendered there by PeopleController#show in the
# default group): every link to a person's page -- the people lists of the
# groups, the start page after the login, redirects, mails -- leads there in
# the primary group, as the person's other pages do
# (Wsjrdp2027::PeopleHelper#other_than_primary_group?). Prepended to the
# route helper modules (lib/hitobito_wsjrdp_2027/wagon.rb).
#
# Only for a person given as a record (not an id: that would cost a query per
# link) whose primary group it is -- a person without one keeps the group's
# URL: the delete link of a group's deleted people, say, returns to that
# group --, for HTML and without options but those of a URL (host, port,
# protocol, locale); everything else is the core's. HTML means no format
# given or format: :html. An explicit format: nil is what the core passes
# on for a client that asked for no particular format (person_home_path
# with request.format.to_sym, Person::TopController's redirect): that one
# keeps the group's URL, so the core's redirect never leads back to
# /people/:id.
module Wsjrdp2027::GroupPersonPaths
  URL_OPTIONS = %i[host port protocol locale].freeze

  # The short form applies to (group, person, options): the group as a record
  # or an id, the person as a record with that primary group.
  def self.short?(args)
    group, person, options = args
    return false unless args.size.between?(2, 3) && person.respond_to?(:primary_group_id)
    return false unless options.nil? || short_options(options)

    group_id = group.respond_to?(:id) ? group.id : group
    person.primary_group_id.present? && group_id.to_s == person.primary_group_id.to_s
  end

  # The options for person_path/_url, nil when they need the group's URL.
  def self.short_options(options)
    return {} if options.nil?
    return nil unless options.is_a?(Hash)

    options = options.symbolize_keys
    return nil if options.key?(:format) && options[:format].to_s != "html"

    rest = options.except(:format)
    rest if (rest.keys - URL_OPTIONS).empty?
  end

  module Path
    def group_person_path(*args)
      return super unless Wsjrdp2027::GroupPersonPaths.short?(args)

      person_path(args[1], Wsjrdp2027::GroupPersonPaths.short_options(args[2]))
    end
  end

  module Url
    def group_person_url(*args)
      return super unless Wsjrdp2027::GroupPersonPaths.short?(args)

      person_url(args[1], Wsjrdp2027::GroupPersonPaths.short_options(args[2]))
    end
  end
end
