# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Plumbing for the Moss card transactions listing: the generic CNF filter
# (doc/generic_filter_builder.md, MossCardTransactionsFilter) compiled to a
# scope, handed to MossCardTransactionsQuery for sort/pagination/columns/sum,
# plus the "Zurücksetzen" clear handling. Mirrors Fin::BookingsFiltering.
module Fin::MossCardTransactionsFiltering
  extend ActiveSupport::Concern

  included do
    helper_method :query, :filter_catalog, :filter_value, :filter_full_catalog
  end

  def query
    @query ||= MossCardTransactionsQuery.new(params, base: filtered_scope, prefix: query_param_prefix)
  end

  def query_param_prefix
    ""
  end

  def filter_param
    query_param_prefix.empty? ? "filter" : "#{query_param_prefix}_filter"
  end

  # --- generic CNF filter plumbing ------------------------------------------

  def filter_bound_schema
    @filter_bound_schema ||= MossCardTransactionsFilter.bound
  end

  # Base page scope the user cannot widen. The bookings LEFT JOIN is required so
  # booking-level attributes (Sachkonto, Kategorie, ...) can be filtered.
  def filter_pinned_scope
    MossCardTransaction.left_joins(:bookings)
  end

  def filter_query
    @filter_query ||= Filtering::UrlCodec.decode(params[filter_param], schema: filter_bound_schema)
  end

  def filtered_scope
    @filtered_scope ||= Filtering::Compiler.new(filter_bound_schema)
      .apply(filter_query, relation: filter_pinned_scope, hidden: MossCardTransactionsFilter::HIDDEN)
  end

  def filter_catalog
    filter_bound_schema.catalog
  end

  def filter_value
    filter_query.as_json
  end

  def filter_full_catalog
    @filter_full_catalog ||= MossCardTransactionsFilter.bound.catalog
  end

  # Shared PRG apply: parse the posted value tree, encode it to Rison and
  # redirect to the shareable GET URL (sort/columns/page-size carried along).
  def apply_filter_and_redirect(target_path)
    tree = begin
      JSON.parse(params[:filter_json].to_s)
    rescue JSON::ParserError
      []
    end
    rison = Filtering::UrlCodec.encode(Filtering::Query.parse(tree), schema: filter_bound_schema)
    page_param = query_param_prefix.empty? ? "page" : "#{query_param_prefix}_page"
    drop = %w[filter_json controller action authenticity_token commit utf8 _method] +
      [filter_param, page_param]
    kept = params.to_unsafe_h.except(*drop)
    parts = kept.to_query.split("&").compact_blank
    parts << "#{filter_param}=#{Filtering::UrlCodec.escape_for_query(rison)}" if rison
    target = parts.any? ? "#{target_path}?#{parts.join("&")}" : target_path
    redirect_to target, status: :see_other
  end

  # "Zurücksetzen": reload the current page without the `clear` marker.
  def handle_clear
    return false unless params.key?(:clear)

    redirect_to "#{request.path}?#{request.query_parameters.except("clear").to_query}"
    true
  end
end
