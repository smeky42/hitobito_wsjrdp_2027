# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Enforces D8.4 of doc/plans/2026-09_expandable-table-state.md: the expandable
# table widget and its helper read the CONTROLLER-RESOLVED Wsjrdp::TableState and
# nothing else. If a partial could reach into params / session / cookies again,
# the security property of the design ("the view can only render what the
# controller resolved") would erode silently -- so it is checked, not asked for.
#
# The ONE exception is link construction: `et_carry_params` and `et_current_path`
# in the helper merge request.query_parameters / request.path so a generated link
# keeps every OTHER param (a sibling table's state, the Kreditoren grid, the
# locale) untouched. Those values are passed through into a URL, never turned
# into state. Any other `request.` use, and every params/session/cookies access,
# is forbidden.
#
# Standalone by design (no rails spec_helper, no DB) -- runs from the wagon root:
#   bundle exec rspec spec/domain/wsjrdp/expandable_table_state_guard_spec.rb
require "pathname"

describe "expandable table state guard (plan D8.4)" do
  let(:wagon_root) { Pathname.new(File.expand_path("../../..", __dir__)) }

  let(:helper_path) { "app/helpers/wsjrdp/expandable_table_helper.rb" }

  # The only methods of the helper that may look at the request, and only for
  # building a URL. Widening this list needs a plan change.
  let(:url_building_methods) { %w[et_carry_params et_current_path] }

  # Reading request state in a view/helper of the widget.
  let(:forbidden) { /\bparams\[|\bsession\[|\bcookies\[|\brequest\./ }
  let(:request_only) { /\brequest\./ }
  let(:comment) { %r{\A\s*(?:#|//|-#|\*|<!--)} }

  # Read explicitly as UTF-8: the partials contain German text and the sort
  # arrows, and a standalone run may default to US-ASCII.
  def lines_of(path)
    path.read(encoding: "UTF-8").lines
  end

  def widget_files
    Pathname.glob(wagon_root.join("app/views/shared/wsjrdp/**/*.haml"))
  end

  def offending_lines(path)
    lines_of(path).each_with_index.filter_map do |line, index|
      next if line.match?(comment)
      next unless line.match?(forbidden)
      "#{path.relative_path_from(wagon_root)}:#{index + 1}: #{line.strip}"
    end
  end

  it "scans the real widget partials" do
    names = widget_files.map { |path| path.basename.to_s }
    expect(names).to include("_expandable_table.html.haml", "_expandable_table_paging.html.haml",
      "_expandable_table_columns_form.html.haml", "_builder.html.haml")
  end

  it "finds no request state in the widget partials" do
    offenders = widget_files.flat_map { |path| offending_lines(path) }
    expect(offenders).to be_empty, <<~MSG
      The expandable table widget must render from its Wsjrdp::TableState only:

        #{offenders.join("\n  ")}

      Resolve the value in the controller (Wsjrdp::TableStateful, the table's
      policy) and read it from the state -- see D8.4 of
      doc/plans/2026-09_expandable-table-state.md.
    MSG
  end

  it "finds no params / session / cookies access in the helper" do
    lines = lines_of(wagon_root.join(helper_path))
    offenders = lines.each_with_index.filter_map do |line, index|
      next if line.match?(comment)
      next unless line.match?(/\bparams\[|\bsession\[|\bcookies\[/)
      "#{helper_path}:#{index + 1}: #{line.strip}"
    end
    expect(offenders).to be_empty, "the helper must read the state, not the request:\n  #{offenders.join("\n  ")}"
  end

  it "uses the request in the helper only inside the URL-building methods" do
    method = nil
    offenders = lines_of(wagon_root.join(helper_path)).each_with_index.filter_map do |line, index|
      method = Regexp.last_match(1) if line =~ /^\s*def\s+([a-z_0-9?!]+)/
      next if line.match?(comment)
      next unless line.match?(request_only)
      next if url_building_methods.include?(method)
      "#{helper_path}:#{index + 1} (in #{method.inspect}): #{line.strip}"
    end
    expect(offenders).to be_empty, <<~MSG
      Only #{url_building_methods.join(" / ")} may touch the request (link
      construction, D1); everything else must come from the state:

        #{offenders.join("\n  ")}
    MSG
  end

  # Guard the guard: a pattern that stopped matching would pass forever.
  it "detects the forbidden patterns in representative samples" do
    samples = ["- open = params[:open].to_s", "- x = session[:foo]",
      "- y = cookies[\"pane\"]", "- z = request.query_parameters"]
    expect(samples).to all(match(forbidden))
  end
end
