# frozen_string_literal: true

require "chartkick"

module HitobitoWsjrdp2027
  class Wagon < Rails::Engine
    include Wagons::Wagon

    # Set the required application version.
    app_requirement ">= 0"

    # Add a load path for this specific wagon
    config.autoload_paths += %W[
      #{config.root}/app/abilities
      #{config.root}/app/domain
      #{config.root}/app/jobs
      #{config.root}/app/controllers
    ]

    config.to_prepare do
      # extend application classes here

      # Models
      Group.include Wsjrdp2027::Group
      Person.include Wsjrdp2027::Person
      Event.include Wsjrdp2027::Event

      # Concerns
      Contactable.prepend Wsjrdp2027::Concerns::Contactable

      # Controllers
      PeopleController.include Wsjrdp2027::PeopleController
      Groups::SelfInscriptionController.include Wsjrdp2027::Groups::SelfInscriptionController
      Group::StatisticsController.include Wsjrdp2027::StatisticsController
      MailingListsController.include Wsjrdp2027::MailingListsController
      Person::QueryController.include Wsjrdp2027::Person::QueryController

      # Decorators
      PersonDecorator.prepend Wsjrdp2027::PersonDecorator

      # Helpers
      Sheet::Base.singleton_class.prepend Wsjrdp2027::Sheet::BaseClass
      Sheet::Base.prepend Wsjrdp2027::Sheet::Base
      Sheet::Person.include Wsjrdp2027::Sheet::Person
      Sheet::Group.include Wsjrdp2027::Sheet::Group
      NavigationHelper.include Wsjrdp2027::NavigationHelper

      # Abilities
      EventAbility.include Wsjrdp2027::EventAbility
      GroupAbility.include Wsjrdp2027::GroupAbility
      PersonAbility.include Wsjrdp2027::PersonAbility
      VariousAbility.include Wsjrdp2027::VariousAbility
      MailingListAbility.include Wsjrdp2027::MailingListAbility
      SubscriptionAbility.include Wsjrdp2027::SubscriptionAbility

      # Other
      Wizards::Steps::NewUserForm.include Wsjrdp2027::Wizards::Steps::NewUserForm
      PersonSerializer.include Wsjrdp2027::PersonSerializer
      Event::ParticipationContactData.include Wsjrdp2027::Event::ParticipationContactData

      ActiveSupport.on_load(:action_view) { include Chartkick::Helper }
    end

    initializer "wsjrdp_2027.add_settings" do |_app|
      Settings.add_source!(File.join(paths["config"].existent, "settings.yml"))
      Settings.reload!
    end

    initializer "wsjrdp_2027.add_inflections" do |_app|
      ActiveSupport::Inflector.inflections do |inflect|
        # inflect.irregular 'census', 'censuses'
      end
    end

    initializer "wsjrdp_2027.assets.precompile" do |app|
      app.config.assets.precompile += %w[
        hitobito_wsjrdp_2027/application.js
      ]
    end

    private

    def seed_fixtures
      fixtures = root.join("db", "seeds")
      ENV["NO_ENV"] ? [fixtures] : [fixtures, File.join(fixtures, Rails.env)]
    end
  end
end
