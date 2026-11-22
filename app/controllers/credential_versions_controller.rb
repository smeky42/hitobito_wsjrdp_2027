# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The versions of an account, for admins: add, change, revoke, re-key and
# delete (doc/wsjrdp/credentials.md, "The pages"). A form that is older
# than the latest change is refused. A flash message never shows a value.
class CredentialVersionsController < ApplicationController
  include Wsjrdp2027::Concerns::BrowserSessionOnly

  STALE = Wsjrdp::Credentials::Kind::Problem.new("base", :stale)

  before_action { authorize!(:manage_credentials, WsjrdpCredential) }
  before_action :find_row, except: [:new, :create]
  before_action :own_stage, only: [:edit, :update, :revoke, :unrevoke, :rekey]
  before_action :find_account, only: [:new, :create]
  before_action :no_store, only: [:new, :create, :edit, :update]

  helper_method :row, :kind, :kind_name, :account_key, :form, :key_problem, :report, :fallback_remains?,
    :overriding_mark

  def new
    name = params[:name]
    name = "" unless Wsjrdp::Credentials.text?(name)
    @form = Wsjrdp::Credentials::VersionForm.blank(kind, public_values: prefill_values,
      further_values: prefill_further_values, name: name)
  end

  def create
    @form = Wsjrdp::Credentials::VersionForm.submitted(kind: kind, params: params[:credential],
      base: Wsjrdp::Credentials::VersionForm.blank(kind))
    return render_failed(:new, field_errors: cast.errors) if form_problems?

    @result = Wsjrdp::Credentials::Deposit.call(kind: kind_name, account_key: account_key,
      values: form.all_values, secret_further_fields: form.secret_further_fields, name: form.name,
      comment: form.comment, author: current_user, **form.instants)
    return render_failed(:new) unless result.saved?

    redirect_to_version(result.record, t(".created"), result.warnings)
  rescue Wsjrdp::Credentials::NoKeyError
    redirect_to credential_path(kind: kind_name, account_key: account_key), alert: t("credentials.notices.no_key")
  end

  def edit
    @form = base_form
  end

  def update
    @form = Wsjrdp::Credentials::VersionForm.submitted(kind: kind, params: params[:credential], base: base_form)
    return render_failed(:edit, field_errors: [], errors: [STALE]) unless form_lock
    return render_failed(:edit, field_errors: changed_field_errors) if form_problems?

    @result = Wsjrdp::Credentials::Change.call(record: row, values: form.changed_values(secrets: key_problem.nil?),
      secret_further_fields: form.secret_further_fields, expected_updated_at: form_lock, **form.changed_attributes)
    return render_failed(:edit) unless result.saved?

    redirect_to_version(row, t(".updated"), result.warnings)
  end

  def revoke = change_revocation(Time.current, t(".revoked"))

  def unrevoke = change_revocation(nil, t(".unrevoked"))

  def rekey
    redirect_after(Wsjrdp::Credentials::Rekey.call(record: row), t(".rekeyed"))
  rescue Wsjrdp::Credentials::NoKeyError
    redirect_to_version(row, nil, [], alert: t("credentials.notices.no_key"))
  end

  def destroy
    row.destroy!
    redirect_to to_account(row.kind, row.account_key), notice: t(".destroyed")
  end

  private

  attr_reader :row, :form, :result

  def find_row = @row = WsjrdpCredential.find(params[:id])

  def own_stage
    return if row.stage == keys.stage

    redirect_to to_account(row.kind, row.account_key), alert: t("credentials.codes.other_stage")
  end

  def find_account
    raise ActiveRecord::RecordNotFound unless kind && Wsjrdp::Credentials.account_key?(account_key)
  end

  def kind_name = row ? row.kind : params[:kind].to_s

  def account_key = row ? row.account_key : Wsjrdp::Credentials.account_key_of(params[:account_key].to_s)

  def kind = kinds[kind_name]

  def kinds = Wsjrdp::Credentials::Kinds.current

  def keys = Wsjrdp::Credentials::Keys.current

  def key_problem = row&.secret_key_problem(keys)

  # The edit form is filled with the current secret values when the
  # version uses the active key. The page is never cached, and an admin
  # may reveal the values anyway.
  def base_form
    opened = row.field_values(keys: keys) if key_problem.nil?
    Wsjrdp::Credentials::VersionForm.of(row, kind: kind, secret_values: opened)
  end

  # An invalid date, or a row of further fields with a problem.
  def form_problems? = form.errors.any? || form.further_problems.any?

  # Only for the field errors of a form with an invalid date or a bad row;
  # Deposit checks the values itself.
  def cast = kind.cast(form.all_values, stage: keys.stage)

  # For a form with an invalid date or a bad row: the errors of the public
  # fields it changes, checked one by one as Change would.
  def changed_field_errors
    form.changed_values(secrets: false).filter_map do |name, text|
      next if text.empty?

      _value, code = (kind.field(name) || kind.further_field(name)).cast(text)
      code && Wsjrdp::Credentials::Kind::Problem.new(name, code)
    end
  end

  def report = @report ||= Wsjrdp::Credentials::Overview.new.account(kind_name, account_key)

  # Whether an older version stays as a fallback: the database is in use
  # and has a usable version.
  def fallback_remains?
    database = report.sources.find { |source| source.source == Wsjrdp::Credentials::DatabaseSource::NAME }
    database.in_use && database.versions.any?(&:role)
  end

  # The mark of the override in use, if any. A new database version would
  # not be used then.
  def overriding_mark = helpers.credential_source_mark(report.in_use)

  # When the row was last changed at the time the form was shown. Change
  # refuses the form if the row changed since. nil if the form sent none.
  def form_lock
    Wsjrdp::InstantInput.parse(params.dig(:credential, :lock).presence&.to_s)
  rescue Wsjrdp::InstantInput::Invalid
    nil
  end

  # The public values of the version in use, to fill a new version.
  # Left out: the title field (it is typed anew) and encrypted fields.
  def prefill_values
    version = report.versions.find { |v| v.role == Wsjrdp::Credentials::Overview::ACTIVE }
    return {} unless version

    credential = version.credential
    (kind.public_field_names - [kind.title_field])
      .select { |name| credential.field_names.include?(name) && !version.record&.sealed?(name) }
      .to_h { |name| [name, credential[name]] }
  end

  # The public further fields of the version in use, never an encrypted one.
  def prefill_further_values
    credential = report.versions.find { |v| v.role == Wsjrdp::Credentials::Overview::ACTIVE }&.credential
    return {} unless credential

    credential.further_field_names.reject { |name| credential.secret_field?(name) }.to_h { |name| [name, credential[name]] }
  end

  def render_failed(template, field_errors: result&.field_errors || [], errors: form.errors + (result&.errors || []))
    @field_errors = field_errors
    @errors = errors
    render template, status: 422
  end

  def change_revocation(revoked_at, notice)
    redirect_after(Wsjrdp::Credentials::Change.call(record: row, revoked_at: revoked_at), notice)
  end

  # Back to the version, with the notice and warnings on success,
  # else with the problems.
  def redirect_after(result, notice)
    if result.saved?
      redirect_to_version(row, notice, result.warnings)
    else
      redirect_to_version(row, nil, [], alert: helpers.credential_problems_text(result.errors + result.field_errors))
    end
  end

  def redirect_to_version(record, notice, warnings, alert: nil)
    flash[:notice] = notice if notice
    flash[:alert] = alert if alert
    flash[:warning] = helpers.credential_problems_text(warnings) if warnings.any?
    redirect_to to_account(record.kind, record.account_key, anchor: "credential-version-#{record.id}")
  end

  def to_account(kind, account_key, **options) = credential_path(kind: kind, account_key: account_key, **options)
end
