require "spec_helper"

GROUP_ACTIONS = [
  # read: show the info page of the group
  :read,
  # show_details: show a few more details about the group
  :show_details,
  # show_statistics: show statistics about the group and the map
  :show_statistics,

  # index_people: list all people in the group
  :index_people,
  # index_local_people: list people in the group that are not visible from above (we don't have this)
  :index_local_people,
  # index_full_people: show *all* columns in export and show all email + phone numbers in people list
  :index_full_people,

  # update: modify group settings (name, contact info, self-registration, letter/sms settings, etc.)
  :update,

  # reactivate: restore a deleted group
  :reactivate,
  # deleted_subgroups: list deleted subgroups
  :deleted_subgroups,

  :activate_person_add_requests,
  :create,
  :create_invoices_from_list,
  :deactivate_person_add_requests,
  :destroy,
  :"export_event/courses",
  :export_events,
  :export_subgroups,
  :index_calendars,
  :index_deep_full_people,
  :index_deleted_people,
  :"index_event/courses",
  :index_events,
  :index_invoices,
  :index_mailing_lists,
  :index_notes,
  :index_person_add_requests,
  :index_service_tokens,
  :log,
  :manage_person_duplicates,
  :manage_person_tags,
  :manually_delete_people,
  :modify_superior,
  :set_main_self_registration_group
]

describe "GROUP_ACTIONS" do
  it "has complete list of actions" do
    defined_actions = Set.new
    Ability.store.configs.values.each do |config|
      if config.subject_class == Group && config.permission != :_class_side
        defined_actions.add(config.action)
      end
    end

    expect(GROUP_ACTIONS).to match_array(defined_actions)
  end
end

shared_examples "only allow group actions" do |params|
  it "can perform allowed actions" do
    allowed_actions = GROUP_ACTIONS.select do |action|
      subject.can?(action, group)
    end
    expect(allowed_actions).to match_array(params[:allowed])
  end

  it "can not perform other actions" do
    forbidden_actions = GROUP_ACTIONS.select do |action|
      subject.cannot?(action, group)
    end
    expect(forbidden_actions).to match_array(GROUP_ACTIONS - params[:allowed])
  end
end
