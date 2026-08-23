# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Builds URL query strings in which the characters "," and "~" stay LITERAL
# instead of percent-encoded ("?sort=bez,nr~" rather than "?sort=bez%2Cnr%7E").
# Both are safe unencoded in a query per RFC 3986 ("," is a sub-delim Rack never
# splits a value on, "~" is unreserved); see doc/url_encoding.md.
#
# SECURITY -- the encapsulation rule (doc/url_encoding.md §6): the %XX -> literal
# "relax" replacement is only safe on the IMMEDIATE output of a proper
# percent-encoder, where a raw "%" cannot occur (every "%" starts a %XX escape,
# so "%2C" can only ever be an encoded comma). This module therefore exposes
# ONLY hash-in/query-string-out -- encode and relax happen inside one method,
# and no public API accepts a pre-built string. Do not add one, and do not
# scatter standalone `.gsub("%2C", ",")` calls elsewhere; widen RELAXATIONS
# only for separator-free characters and only together with new spec coverage
# (spec/models/relaxed_url_query_spec.rb).
module RelaxedUrlQuery
  # %XX escape => literal character. Only characters that no parser in our stack
  # treats as a separator may ever be listed here (NEVER "&" %26, "=" %3D,
  # "+" %2B, "#" %23, "%" %25, ";" %3B while unverified). Keys must be the
  # UPPERCASE hex form, which is what ERB/CGI/to_query emit.
  RELAXATIONS = {
    "%2C" => ",",
    "%7E" => "~"
  }.freeze

  RELAXATION_PATTERN = Regexp.union(RELAXATIONS.keys).freeze

  # Private so the pieces cannot be reassembled into the forbidden raw-string
  # relax from outside (`str.gsub(RelaxedUrlQuery::RELAXATION_PATTERN, ...)`).
  # The spec reaches them via const_get, which bypasses this deliberately.
  private_constant :RELAXATIONS, :RELAXATION_PATTERN

  module_function

  # params (Hash, may be nested / contain arrays) -> query string with the
  # RELAXATIONS applied, e.g. {sort: "bez,nr~"} -> "sort=bez,nr~". Returns "" for
  # blank params. The only public entry point: encoding (Rails Hash#to_query,
  # which percent-encodes every "%" as %25) and relaxing are one step, so the
  # relax can never touch a string containing a raw "%".
  #
  # Only a Hash is accepted -- explicitly, not by accident. A String would also
  # raise (String#to_query needs a key), but relying on that would make the core
  # safety property an implementation detail of Rails; anything already encoded
  # must never reach the relax step. Mirrors the JS helper's TypeError.
  def to_query(params)
    unless params.is_a?(Hash)
      raise TypeError, "RelaxedUrlQuery.to_query expects a Hash, got #{params.class}"
    end
    params.to_query.gsub(RELAXATION_PATTERN, RELAXATIONS)
  end
end
