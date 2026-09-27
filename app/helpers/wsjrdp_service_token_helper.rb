# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The token column as the core's attribute list shows it (format_attr looks
# for format_<model>_<attr>): which of the three forms it holds, the stage and
# the secret's fingerprint of an HMAC token hash, and whether the token works here
# (Wsjrdp2027::ServiceToken).
module WsjrdpServiceTokenHelper
  def format_service_token_token(service_token)
    stored = service_token.token.to_s
    scheme = ::ServiceToken.token_scheme(stored)
    reach = service_token.token_reach
    safe_join([
      content_tag(:code, stored),
      muted(t("service_tokens.token.#{scheme}", stage: service_token_stage_name(service_token.stage))),
      (service_token_fingerprint_line(service_token) if scheme == :hmac),
      (muted(t("service_tokens.token.reach.#{reach}")) unless reach == :everywhere)
    ].compact, tag.br)
  end

  # The fingerprint of the HMAC secret, or that it is not known yet.
  def service_token_fingerprint_line(service_token)
    fingerprint = service_token.hmac_secret_key_fingerprint
    return muted(t("service_tokens.token.fingerprint_unknown")) if fingerprint.blank?

    muted(safe_join([t("service_tokens.token.fingerprint"), " ", content_tag(:code, fingerprint)]))
  end

  # "Token-Hash" for a hash, "Token" for a token stored as it is.
  def service_token_token_label(service_token)
    kind = ::ServiceToken.hashed_token?(service_token.token) ? :hashed : :plain
    t("service_tokens.token.label.#{kind}")
  end

  def service_token_stage_name(stage)
    t("service_tokens.token.stages.#{stage}", default: stage.to_s)
  end
end
