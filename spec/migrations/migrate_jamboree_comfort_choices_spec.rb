# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"
require HitobitoWsjrdp2027::Wagon.root.join("db/migrate/20261015000100_migrate_jamboree_comfort_choices.rb")

# The comfort answers keep their meaning (a stored true was a ticked "wohl");
# the missing ones are filled: all true when nothing was answered, false next
# to an answer. Each person changed gets a version, which down reads.
describe MigrateJamboreeComfortChoices do
  let(:migration) { described_class.new }
  let(:attrs) { described_class::COMFORT_ATTRS }
  let(:untouched) { people(:yp_a_1) }
  let(:some) { people(:ul_a_1) }
  let(:all) { people(:yp_a_2) }
  let(:complete) { people(:cmt_leader) }

  def quietly(&block) = ActiveRecord::Migration.suppress_messages(&block)

  def stored(person) = Person.where(id: person.id).pick(:jamboree_data)

  def versions = PaperTrail::Version.where(mutation_id: described_class::MUTATION)

  before do
    untouched.update_columns(jamboree_data: {"known_as_name" => "Kim"})
    some.update_columns(jamboree_data: {"comfortable_on_water" => true, "comfortable_in_crowd" => true})
    all.update_columns(jamboree_data: attrs.index_with(true))
    complete.update_columns(jamboree_data: attrs.index_with(false).merge("comfortable_in_water" => true))
  end

  it "fills the missing answers, keeps the given ones and leaves a version per person changed" do
    before = [all, complete].index_with { |person| stored(person) }
    quietly { migration.migrate(:up) }

    expect(stored(untouched)).to eq(attrs.index_with(true).merge("known_as_name" => "Kim"))
    expect(stored(some)).to eq(attrs.index_with(false).merge("comfortable_on_water" => true,
      "comfortable_in_crowd" => true))
    before.each { |person, data| expect(stored(person)).to eq(data) }

    expect(versions.pluck(:item_id)).to include(untouched.id, some.id)
    expect(versions.pluck(:item_id)).not_to include(all.id, complete.id)
    version = versions.find_by(item_id: some.id)
    expect(version).to have_attributes(item_type: "Person", event: "update", main_type: "Person",
      main_id: some.id, whodunnit: "1")
    expect(version.changeset).to eq((attrs - %w[comfortable_on_water comfortable_in_crowd])
      .index_with([nil, false]))
    expect(versions.find_by(item_id: untouched.id).changeset).to eq(attrs.index_with([nil, true]))
  end

  it "changes nothing more when run again" do
    quietly { migration.migrate(:up) }
    data = Person.order(:id).pluck(:id, :jamboree_data)

    expect { quietly { migration.migrate(:up) } }.not_to change { versions.count }
    expect(Person.order(:id).pluck(:id, :jamboree_data)).to eq(data)
  end

  it "takes the filled answers out again" do
    data = Person.order(:id).pluck(:id, :jamboree_data)
    quietly { migration.migrate(:up) }
    quietly { migration.migrate(:down) }

    expect(Person.order(:id).pluck(:id, :jamboree_data)).to eq(data)
    expect(versions).to be_empty
  end
end
