# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# GET /api/documents?filter[subject_id]=... and GET /api/documents/:id
# (DocumentResource). The list holds only the documents the caller may
# read; it needs filter[subject_id].
class JsonApi::DocumentsController < JsonApiController
  def index
    authorize!(:index, WsjrdpDocument)
    raise ActionController::BadRequest, "filter[subject_id] is required" if DocumentResource.subject_ids(params).empty?

    super
  end

  def show
    authorize!(:show, WsjrdpDocument.find(params[:id]))
    super
  end
end
