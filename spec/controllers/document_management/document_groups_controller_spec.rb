# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The tab Nach Person und Art of the main section Dokumente: the documents
# grouped by person and kind, for admins only.
describe DocumentManagement::DocumentGroupsController, type: :controller do
  before_all(setup_fixtures: true) do
    @admin = Fabricate(Group::Root::Admin.name.to_sym, group: groups(:root)).person
  end

  let(:person) { people(:yp_a_1) }
  let(:root) { Pathname(Dir.mktmpdir("wsjrdp-documents")) }

  before do
    allow(Wsjrdp2027::DocumentStore).to receive(:root).and_return(root)
    sign_in(@admin)
  end

  after { FileUtils.rm_rf(root) }

  def store(key, subject: person, **options)
    Wsjrdp2027::DocumentStore.store!(StringIO.new("%PDF-1.4 #{SecureRandom.hex(4)}"),
      {subject: subject, key: key, filename: "#{key}.pdf"}.merge(options))
  end

  def shown = controller.send(:groups).page.to_a

  def group_of(subject, key) = shown.find { |group| group.subject_id == subject.id && group.key == key }

  it "is refused to who is no admin" do
    sign_in(people(:cmt_leader))

    expect { get :index }.to raise_error(CanCan::AccessDenied)
  end

  it "groups the documents by person and kind, whatever their numbers" do
    first = store("deregistration", key_number: 1)
    store("deregistration", key_number: 1, replaces: first)
    second = store("deregistration", key_number: 2)
    Wsjrdp2027::DocumentStore.hide!(second)
    store("deregistration", subject: people(:yp_a_2), key_number: 1)

    get :index

    expect(shown.count { |group| group.key == "deregistration" }).to eq(2)
    expect(group_of(person, "deregistration"))
      .to have_attributes(count: 3, combinations: 2, current: 1, superseded: 1, deleted: 1, current_state: :some)
  end

  it "orders the groups by the latest upload, then by person, then by the kind's position" do
    other = people(:yp_a_2)
    at = 2.days.ago.beginning_of_minute
    [[person, "medical"], [person, "contract"], [person, "deregistration"], [other, "sepa"], [other, "passport"]]
      .each do |subject, key|
        store(key, subject: subject).update_columns(created_at: (key == "passport") ? at + 1.hour : at)
      end
    expect(person.to_s.downcase).to be < other.to_s.downcase

    get :index, params: {s: ""}

    expect(shown.map(&:key) & %w[medical contract deregistration sepa passport])
      .to eq(%w[passport contract medical deregistration sepa])
  end

  it "counts only the filtered documents in a group" do
    first = store("deregistration")
    store("deregistration", replaces: first)
    schema = DocumentManagement::DocumentsFilterSchema
    current = schema.encode(Wsjrdp::Filtering::Query.parse([[%w[status in current]]]), schema: schema.bound)

    get :index, params: {f: current}

    expect(group_of(person, "deregistration").count).to eq(1)
  end

  it "shows a group with its versions by their numbers" do
    store("deregistration", key_number: 2)
    store("deregistration", key_number: 1)

    get :show, params: {id: "person-#{person.id}-deregistration"}

    expect(response).to have_http_status(200)
    expect(assigns(:document_group).versions.map(&:key_number)).to eq([1, 2])
  end

  # A parameter that is not canonical is DocumentManagement::DocumentGroups' to refuse.
  it "answers 404 for a group parameter that names no documents" do
    store("deregistration")

    expect { get :show, params: {id: "person-#{person.id}-medical"} }.to raise_error(ActiveRecord::RecordNotFound)
  end
end
