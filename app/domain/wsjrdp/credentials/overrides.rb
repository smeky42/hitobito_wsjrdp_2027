# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp::Credentials
  # The two overrides of this instance, the sources of the lookup in front
  # of the database: the variables, then the local file. .current reads
  # them once at boot and logs a summary; .reload! reads them again.
  class Overrides < Data.define(:variables, :file)
    include Undumpable

    class << self
      def current
        @current ||= build.tap { |overrides| overrides.log_summary(Rails.logger) }
      end

      # Reads the overrides again, and the keys with them, in this process
      # only. A problem raises ConfigurationError and keeps the old ones.
      def reload!
        overrides = build
        Keys.from_sources(file: overrides.file)
        @current = overrides.log_summary(Rails.logger)
        Keys.reset!
        Keys.current
        self
      end

      # test: whether this is the Rails environment test, which does not
      # read the file.
      def build(env: captured_variables, path: LocalFile::PATH, stage: Keys.stage, kinds: Kinds.current, test: Rails.env.test?)
        new(variables: Variables.new(env, stage: stage, kinds: kinds),
          file: LocalFile.for_instance(path, stage: stage, kinds: kinds, test: test))
      end

      def captured_variables = Wsjrdp::Credentials.captured(Rails.configuration.x.credential_variables) || {}
    end

    def sources = [variables, file]

    def log_summary(logger)
      variables.log_summary(logger)
      file.log_summary(logger)
      self
    end

    def as_json(*) = {"variables" => variables.as_json, "file" => file.as_json}
  end
end
