class AccountingEntriesController < ApplicationController
  include FormatHelper
  include UtilityHelper
  include ::ActionView::Helpers::TagHelper

  before_action :authorize_action
  decorates :group, :person

  helper_method :accounting_entry
  helper_method :can_accounting?
  helper_method :get_accounting_entry_cancel_url
  helper_method :get_accounting_entry_path
  helper_method :get_accounting_entry_return_url
  helper_method :person

  def show
    @group ||= group
    @person ||= person
    @accounting_entry ||= accounting_entry
    render "person/accounting_entries/show"
  end

  def update
    @group ||= group
    @person ||= person
    @accounting_entry ||= accounting_entry

    unless params[:accounting_entry].blank?
      new_comment = params[:accounting_entry][:comment]
      new_comment ||= ""
      accounting_entry.comment = new_comment
      unless accounting_entry.save
        render "person/accounting_entries/show", status: :bad_request
        return
      end
    end
    redirect_to get_accounting_entry_return_url
  end

  def accounting_entry
    @accounting_entry ||= AccountingEntry.find(params[:id])
  end

  def person
    @person ||= accounting_entry.person
  end

  def group
    @group ||= person.primary_group
  end

  def get_accounting_entry_path(entry = nil)
    accounting_entry_path(accounting_entry)
  end

  def can_accounting?
    can?(:log, person)
  end

  def authorize_action
    authorize!(:log, person)
  end

  def form_like_labeled_attrs(obj, *attrs)
    safe_join(attrs.map { |a| form_like_labelled_attr(obj, a) })
  end

  def form_like_labeled_attr(obj, attr, display_link: true)
    key = captionize(attr, object_class(obj))
    val = format_attr(obj, attr, display_link: display_link)
    key_content = content_tag(:span, key, class: "col-md-3 col-xl-2 text-md-end")
    val_content = content_tag(:span, val, class: "labeled pb-1 col-md-9 col-lg-8 col-xl-8 mw-63ch")
    content_tag(:div, key_content + val_content, class: "row mb-2")
  end

  def form_like_render_attrs(obj, *attrs, display_link: true)
    return if attrs.blank?

    content = safe_join(attrs) do |a|
      form_like_labeled_attr(obj, a, display_link: display_link) if !block_given? || yield(a)
    end
    content_tag(:div, content, class: "dl-horizontal m-0 p-2 border-top") if content.present?
  end
  helper_method :form_like_render_attrs

  private

  def safe_join(array, sep = $OUTPUT_FIELD_SEPARATOR, &block)
    if block
      array = array.collect(&block).compact
    end
    super(array, sep)
  end

  def _url_host_allowed?(url)
    URI(url.to_s).host == request.host
  rescue ArgumentError, URI::Error
    false
  end

  def get_accounting_entry_cancel_url
    get_accounting_entry_return_url
  end

  def get_accounting_entry_return_url
    if params[:return_url].present?
      params[:return_url]
    elsif request.referer && _url_host_allowed?(request.referer)
      request.referer
    else
      "#{group_person_path(group, person)}/accounting"
    end
  end
end
