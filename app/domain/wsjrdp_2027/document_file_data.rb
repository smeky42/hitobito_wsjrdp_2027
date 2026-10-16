# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027
  # What a document row says about its file (wsjrdp_documents.content_type,
  # byte_size, content_sha256), read from the file -- for a file that is
  # registered (RegistrationDocuments::Import) or found again
  # (DocumentFileCheck).
  module DocumentFileData
    module_function

    # The type by the file's content and name, its size and SHA-256.
    def of(path, filename:)
      {content_type: Marcel::MimeType.for(Pathname(path), name: filename), byte_size: File.size(path),
       content_sha256: Digest::SHA256.file(path).hexdigest}
    end
  end
end
