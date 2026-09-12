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
      # Role first: Group::Root's role classes use admin_only_assignment at
      # class-definition time, and including Wsjrdp2027::Group loads them. It
      # must also precede the permission registration below: that references
      # Role, which can pull the role classes in with it -- and they would then
      # be defined before admin_only_assignment exists.
      Role.include Wsjrdp2027::Role

      # Own permissions, extending the core's Role::Permissions (the
      # core keeps that constant mutable precisely to allow this). Our
      # finance access adds :finance_read, :finance_audit and
      # :finance_manage to the core's :finance.
      #
      # This MUST run before the ability concerns further down: AbilityDsl's
      # recorder rejects any permission missing from Role::Permissions
      # ("Unknown permission"), and the concerns register their rules on
      # `include`. It belongs in to_prepare rather than an initializer because
      # Role is autoloaded (and is reloaded in development, which resets the
      # constant) -- hence also the idempotence guard.
      %i[finance_read finance_audit finance_manage].each do |permission|
        Role::Permissions << permission unless Role::Permissions.include?(permission)
      end
      # Marks the tier as write-granting. The core only defines this constant
      # and does not read it (yet); the entry keeps the semantics right should
      # it start to.
      unless Role::WRITING_PERMISSIONS.include?(:finance_manage)
        Role::WRITING_PERMISSIONS << :finance_manage
      end
      # AbilityDsl::UserContext only builds its group/layer lookup for the
      # permissions listed here (init_permission_groups / init_permission_layers),
      # and both constants are explicitly meant to be extended. Without this,
      # permission_layer_ids(:finance_read) would simply return nil and every
      # constraint built on it would fail. Both are layer-scoped, like :finance.
      %i[finance_read finance_audit finance_manage].each do |permission|
        unless AbilityDsl::UserContext::GROUP_PERMISSIONS.include?(permission)
          AbilityDsl::UserContext::GROUP_PERMISSIONS << permission
        end
        unless AbilityDsl::UserContext::LAYER_PERMISSIONS.include?(permission)
          AbilityDsl::UserContext::LAYER_PERMISSIONS << permission
        end
      end

      Group.include Wsjrdp2027::Group
      Person.include Wsjrdp2027::Person
      Event.include Wsjrdp2027::Event
      AdditionalEmail.include Wsjrdp2027::AdditionalEmail
      ActsAsTaggableOn::Tagging.include Wsjrdp2027::ActsAsTaggableOn::Tagging

      # Concerns
      Contactable.prepend Wsjrdp2027::Concerns::Contactable

      # Controllers
      PeopleController.prepend Wsjrdp2027::PeopleController
      GroupsController.prepend Wsjrdp2027::GroupsController
      Groups::SelfInscriptionController.include Wsjrdp2027::Groups::SelfInscriptionController
      Group::StatisticsController.include Wsjrdp2027::StatisticsController
      MailingListsController.include Wsjrdp2027::MailingListsController
      Person::QueryController.include Wsjrdp2027::Person::QueryController

      # Decorators
      PersonDecorator.prepend Wsjrdp2027::PersonDecorator
      ContactableDecorator.prepend Wsjrdp2027::ContactableDecorator
      PaperTrail::VersionDecorator.prepend Wsjrdp2027::PaperTrail::VersionDecorator

      # Helpers
      Sheet::Base.singleton_class.prepend Wsjrdp2027::Sheet::BaseClass
      Sheet::Base.prepend Wsjrdp2027::Sheet::Base
      Sheet::Person.include Wsjrdp2027::Sheet::Person
      Sheet::Group.include Wsjrdp2027::Sheet::Group
      NavigationHelper.include Wsjrdp2027::NavigationHelper
      StandardFormBuilder.prepend Wsjrdp2027::StandardFormBuilder

      # Abilities
      EventAbility.include Wsjrdp2027::EventAbility
      GroupAbility.include Wsjrdp2027::GroupAbility
      PersonAbility.include Wsjrdp2027::PersonAbility
      VariousAbility.include Wsjrdp2027::VariousAbility
      MailingListAbility.include Wsjrdp2027::MailingListAbility
      SubscriptionAbility.include Wsjrdp2027::SubscriptionAbility
      RoleAbility.include Wsjrdp2027::RoleAbility

      # Other
      Wizards::Steps::NewUserForm.include Wsjrdp2027::Wizards::Steps::NewUserForm
      PersonSerializer.include Wsjrdp2027::PersonSerializer
      Event::ParticipationContactData.include Wsjrdp2027::Event::ParticipationContactData

      PaperTrail::Events::Base.include Wsjrdp2027::PaperTrail::Events::Base

      ActiveSupport.on_load(:action_view) { include Chartkick::Helper }
    end

    # Role carries admin_only_assignment, and the group role classes use it at
    # CLASS-DEFINITION time (Group::Root::Admin, Group::Extern::FinanceAuditor,
    # ...). A to_prepare include is not enough: after a code reload a role class
    # can be autoloaded before to_prepare has re-included the concern, and the
    # class body then dies with
    #   NoMethodError: undefined method `admin_only_assignment='
    # (reproducible in development: touch any of those files, the FIRST request
    # afterwards fails, the second succeeds). Zeitwerk's on_load fires exactly
    # when Role is defined -- on every load, reloads included -- so the
    # attribute is guaranteed to exist before any subclass body runs.
    initializer "wsjrdp_2027.role_extensions" do |_app|
      Rails.autoloaders.main.on_load("Role") do |klass, _abspath|
        klass.include Wsjrdp2027::Role
      end
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
        hitobito_wsjrdp_2027/turbo_stream_actions.js
      ]
    end

    private

    def seed_fixtures
      fixtures = root.join("db", "seeds")
      ENV["NO_ENV"] ? [fixtures] : [fixtures, File.join(fixtures, Rails.env)]
    end
  end
end
