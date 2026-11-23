# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# For the Synchronisation specs: a stand-in for Wsjrdp::Moss::Client that
# answers every list from the made-up fixture, and a folder for the files.
module SyncSpecHelpers
  FIXTURE = "spec/fixtures/files/moss/organisation_structure.json"

  class FakeMossClient
    attr_reader :lists, :transcript

    def self.lists = JSON.parse(HitobitoWsjrdp2027::Wagon.root.join(FIXTURE).read).slice("departments", "teams", "users")

    def initialize
      @lists = self.class.lists
      @transcript = Wsjrdp::Moss::Transcript.new
    end

    def all(path, _params = {}, page_size: 100) = lists.fetch(path.delete_prefix("v1/")).deep_dup

    def total_items(path) = lists.fetch(path.delete_prefix("v1/")).size
  end

  def self.included(group)
    group.let(:client) { FakeMossClient.new }
    group.let(:lists) { client.lists }
    group.let!(:sync_root) { Pathname(Dir.mktmpdir) }
    group.before { allow(Wsjrdp::Sync::Files).to receive(:root).and_return(sync_root) }
    group.after { FileUtils.remove_entry(sync_root) }
  end
end
