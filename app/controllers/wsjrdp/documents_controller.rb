# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The stored documents (doc/wsjrdp/documents.md), whatever their subject:
#
# - GET /documents/:id sends the file, inline or with ?download=1 as an
#   attachment. Only types a browser shows without running anything are sent
#   inline; every answer forbids caching and runs in a sandbox. A file that
#   is missing (file_status missing, not found, or no path) answers 404.
# - POST /documents stores an upload (wsjrdp/documents/_upload_form): the
#   subject, its keys, the document it replaces, a date and a comment come
#   with it. Who may read, write and hide the new document follows from the
#   one it replaces, its kind (WsjrdpDocumentKind) or the defaults; only an
#   admin may give the three lists with the request. A subject whose data
#   is not valid does not refuse the upload; the answer warns (#store).
#   While another write of the subject's documents holds their lock past
#   the timeout (Wsjrdp::LockedChange::Busy), or the database ends the
#   write in a deadlock, nothing is written and the answer asks to try
#   again.
#
# Who may do what is the document's own lists (Wsjrdp2027::DocumentAccess).
class Wsjrdp::DocumentsController < ApplicationController
  INLINE_TYPES = %w[application/pdf image/png image/jpeg image/gif image/webp text/plain].freeze
  SLOT_PARAMS = %i[key key_number secondary_key secondary_key_number].freeze
  RIGHTS_PARAMS = %i[readable_by writable_by deletable_by].freeze

  # create authorizes the document as built, before anything is written
  # (DocumentStore.store!'s block), and the one it replaces.
  skip_authorization_check only: :create

  def show
    document = WsjrdpDocument.find(params[:id])
    authorize!(:show, document)
    path = file_path(document)
    return render(plain: t(".missing"), status: :not_found) unless path

    response.headers["Cache-Control"] = "private, no-store"
    response.headers["Content-Security-Policy"] = "sandbox"
    send_file path, filename: File.basename(path), type: document.content_type,
      disposition: disposition(document)
  end

  def create
    upload = document_params[:file]
    return redirect_back_or_to(root_path, alert: t(".no_file")) unless upload.respond_to?(:original_filename)

    document, warnings = store(upload)
    flash[:warning] = warnings.join(" ") if warnings.any?
    redirect_back_or_to(fallback_path(document), notice: t(".stored", filename: document.filename))
  rescue ActiveRecord::RecordInvalid => e
    redirect_back_or_to(root_path, alert: e.record.errors.full_messages.to_sentence)
  rescue Wsjrdp2027::DocumentStore::TooLarge => e
    redirect_back_or_to(root_path,
      alert: t(".too_large", size: e.limit_mb || Settings.documents.max_upload_size_mb))
  rescue ArgumentError => e
    redirect_back_or_to(root_path, alert: e.message)
  rescue Wsjrdp::LockedChange::Busy, ActiveRecord::Deadlocked
    redirect_back_or_to(root_path, alert: t(".busy"))
  end

  private

  # As DocumentStore.store!, but a subject whose data is not valid (e.g. a
  # person as it lies in the database) does not refuse the upload: the
  # document and the people column of its kind are written anyway, and the
  # answer shows the warning of DocumentWrite. Answers the document and the
  # warnings.
  def store(upload)
    attributes = attributes(upload)
    write = Wsjrdp2027::DocumentWrite.new(skip_unchanged: false)
    write.put(upload, attributes, expected_current: attributes[:replaces]) { |built| authorize!(:create, built) }
    [write.commit!.first.document, write.warnings]
  end

  def document_params
    params.require(:document).permit(:subject_type, :subject_id, :replaces_id, :document_date, :comment,
      :file, *SLOT_PARAMS, *RIGHTS_PARAMS, RIGHTS_PARAMS.index_with { [] })
  end

  # The lists an admin gave (the tag selects of the form, or a text "log,
  # finance"); an empty one leaves the kind's. None for anybody else.
  def given_rights
    return {} unless Wsjrdp2027::DocumentAccess.new(current_ability).admin?

    RIGHTS_PARAMS.each_with_object({}) do |list, rights|
      entries = Array(document_params[list]).flat_map { |part| part.to_s.split(/[\s,]+/) }.compact_blank
      next if entries.empty?

      bad = entries.grep_v(WsjrdpDocumentKind::ENTRY_FORMAT)
      raise ArgumentError, t("wsjrdp.documents.create.invalid_entries", entries: bad.join(", ")) if bad.any?

      rights[list] = entries
    end
  end

  # The subject and keys from the form; a replacement takes those of the
  # document it replaces, which the person must be allowed to change.
  def attributes(upload)
    common = {filename: upload.original_filename, content_type: upload.content_type,
              author: current_user, origin: "ui", comment: document_params[:comment].to_s,
              document_date: document_params[:document_date].presence}.merge(given_rights)
    if document_params[:replaces_id].present?
      replaces = WsjrdpDocument.find(document_params[:replaces_id])
      authorize!(:update, replaces)
      return common.merge(subject: replaces.subject, replaces: replaces)
    end

    slot = document_params.slice(*SLOT_PARAMS).to_h.symbolize_keys
    slot[:secondary_key] = slot[:secondary_key].to_s
    common.merge(slot).merge(subject: subject)
  end

  def subject
    type = document_params[:subject_type].to_s
    raise ActiveRecord::RecordNotFound, "unknown subject type" unless Wsjrdp2027::DocumentSubjects.known?(type)

    type.constantize.find(document_params[:subject_id])
  end

  # The file of the document, nil when it is missing, has no path or a path
  # the store refuses.
  def file_path(document)
    return nil if document.file_missing? || document.relative_storage_file_path.blank?

    path = Wsjrdp2027::DocumentStore.path_for(document)
    File.file?(path) ? path : nil
  rescue ArgumentError
    nil
  end

  def disposition(document)
    inline = params[:download].blank? && INLINE_TYPES.include?(document.content_type)
    inline ? "inline" : "attachment"
  end

  def fallback_path(document)
    document.subject.is_a?(Person) ? person_path(document.subject) : root_path
  end
end
