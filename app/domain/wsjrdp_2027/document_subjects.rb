# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027
  # The kinds of subject a document may belong to (wsjrdp_documents.subject_type)
  # and per kind:
  # - folder: where its files lie, relative to the upload root;
  # - entries: the access entries that mean something for it
  #   (Wsjrdp2027::DocumentAccess); the finance tiers mean something for
  #   every kind.
  #
  # Only Person is a kind so far; a document of another subject is refused
  # (WsjrdpDocument validates subject_type). A new kind also needs what
  # Person#soft_delete_wsjrdp_documents does for a person: hide its documents
  # when the subject is destroyed. Its subject_id must stay a non-negative
  # integer, as the file name holds it (Wsjrdp2027::DocumentFilename).
  module DocumentSubjects
    Kind = Data.define(:type, :folder, :entries) do
      def folder_for(subject_id) = format(folder, id: Integer(subject_id))
    end

    # The folder of a person is the one of the registration uploads; it holds
    # files of every type, not only PDFs.
    KINDS = {
      "Person" => Kind.new(type: "Person", folder: "person/pdf/%<id>d", entries: %w[person log update])
    }.freeze

    module_function

    def types = KINDS.keys

    def known?(type) = KINDS.key?(type.to_s)

    def fetch(type) = KINDS.fetch(type.to_s)

    # The kind's name in a URL, the model's Rails param key ("person" for
    # Person, "event_course" for Event::Course), and back; nil for a type or
    # token that is no kind. Only the kinds' own names are constantized, never
    # what a request brings.
    def param_for(type) = params.key(type.to_s)

    def type_for_param(token) = params[token.to_s]

    def params
      @params ||= KINDS.keys.index_by { |type| type.constantize.model_name.param_key }.freeze
    end
  end
end
