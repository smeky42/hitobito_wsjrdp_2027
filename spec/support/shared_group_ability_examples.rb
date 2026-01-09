require "spec_helper"

GROUP_ACTIONS = [
  # read: show the info page of the group
  :read,
  # show_details: show a few more details about the group
  :show_details,

  # index_people: list all people in the group
  :index_people,
  # index_local_people: list people in the group that are not visible from above (we don't have this)
  :index_local_people,

  :activate_person_add_requests,
  :create,
  :create_invoices_from_list,
  :deactivate_person_add_requests,
  :deleted_subgroups,
  :destroy,
  :"export_event/courses",
  :export_events,
  :export_subgroups,
  :index_calendars,
  :index_deep_full_people,
  :index_deleted_people,
  :"index_event/courses",
  :index_events,
  :index_full_people,
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
  :reactivate,
  :set_main_self_registration_group,
  :show_statistics,
  :update
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
    params[:allowed].each do |action|
      is_expected.to be_able_to(action, group)
    end
  end

  it "can not perform other actions" do
    (GROUP_ACTIONS - params[:allowed]).each do |action|
      is_expected.to_not be_able_to(action, group)
    end
  end
end
