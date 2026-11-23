# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp::Sync
  # The files of the runs, in one folder, each name starting with the run's
  # start in UTC (doc/fin/sync.md, "Files"):
  #
  #   20261123T142501Z_run-42_moss_api.organisation_structure.users.data-users.json
  module Files
    STAMP = "%Y%m%dT%H%M%SZ"
    NAME = /\A(?<stamp>\d{8}T\d{6}Z)_run-\d+_[a-z0-9_.-]+\.json\z/
    # A write goes to ".tmp-<random>-<name>" first, then is renamed.
    TEMPORARY = /\A\.tmp-\h{16}-/
    DATA_PREFIX = "data-"
    META = "meta"

    class Missing < StandardError; end

    # <wagon>/private/sync (backed up); in tests tmp/sync.
    def self.root = HitobitoWsjrdp2027::Wagon.root.join(Rails.env.test? ? "tmp/sync" : "private/sync")

    def self.name(run, part_key, file) = "#{run.started_at.utc.strftime(STAMP)}_run-#{run.id}_#{part_key}.#{file}.json"

    # Writes content as JSON and returns the entry the part keeps.
    def self.write(run, part_key, file, content)
      FileUtils.mkdir_p(root)
      name = name(run, part_key, file)
      text = JSON.generate(content)
      temporary = root.join(".tmp-#{SecureRandom.hex(8)}-#{name}")
      File.write(temporary, text)
      File.rename(temporary, root.join(name))
      {"name" => name, "file" => file, "size" => text.bytesize, "sha256" => Digest::SHA256.hexdigest(text)}
    end

    # The content of an entry; raises Missing when the file is gone or no
    # longer the one written.
    def self.read(entry)
      path = root.join(entry.fetch("name"))
      raise Missing, "#{entry["name"]} is gone" unless File.file?(path)

      text = File.read(path)
      raise Missing, "#{entry["name"]} has changed" unless Digest::SHA256.hexdigest(text) == entry["sha256"]

      JSON.parse(text)
    end

    # The data files of a part, as {name => content}.
    def self.data(entries)
      entries.select { |entry| entry["file"].to_s.start_with?(DATA_PREFIX) }
        .to_h { |entry| [entry["file"].delete_prefix(DATA_PREFIX), read(entry)] }
    end

    # Deletes the files of runs started before the given time, and what an
    # interrupted write of theirs left behind; returns how many. Only names
    # of this scheme are touched.
    def self.purge(before:)
      return 0 unless File.directory?(root)

      cutoff = before.utc.strftime(STAMP)
      Dir.children(root).count do |name|
        match = NAME.match(name.sub(TEMPORARY, ""))
        next false unless match && match[:stamp] < cutoff

        File.delete(root.join(name))
        true
      end
    end
  end
end
