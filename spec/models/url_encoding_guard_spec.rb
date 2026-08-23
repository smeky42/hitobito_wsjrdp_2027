# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Enforces the encapsulation rule of doc/url_encoding.md §6: the %XX -> literal
# "relax" replacement may exist ONLY inside the two mandatory helpers, because it
# is safe only on the immediate output of a percent-encoder. Anywhere else it can
# hit a string containing a raw "%" and corrupt data or forge separators.
#
# Standalone by design (no rails spec_helper, no DB) -- runs from the core app
# directory inside the dev container:
#   bundle exec rspec ../hitobito_wsjrdp_2027/spec/models/url_encoding_guard_spec.rb
require "pathname"

describe "URL-encoding guard (doc/url_encoding.md §6)" do
  let(:wagon_root) { Pathname.new(File.expand_path("../..", __dir__)) }

  # The only two places a %XX relax may appear. Widening this list is a policy
  # change -- see doc/url_encoding.md §6.1.
  let(:allowed) do
    ["app/models/relaxed_url_query.rb",
      "app/views/shared/_relaxed_query_js.html.haml"]
  end

  let(:scanned_globs) do
    %w[app/**/*.rb app/**/*.haml app/**/*.erb app/**/*.js lib/**/*.rb lib/**/*.rake]
  end

  # A string/regexp replacement whose pattern starts with a percent escape, e.g.
  # .gsub("%2C", ","), .replace(/%7E/gi, "~"), .tr('%2C', ',').
  let(:relax_call) do
    /\.(?:gsub|gsub!|sub|sub!|replace|tr|tr!)\s*\(?\s*(?:["']%[0-9A-Fa-f]{2}|\/%[0-9A-Fa-f]{2})/
  end

  # Comment lines -- the doc and call sites legitimately *describe* the pattern.
  let(:comment) { /\A\s*(?:#|\/\/|-#|\*|<!--)/ }

  def offending_lines(path, root)
    path.read.lines.each_with_index.filter_map do |line, i|
      next if line.match?(comment)
      next unless line.match?(relax_call)
      "#{path.relative_path_from(root)}:#{i + 1}: #{line.strip}"
    end
  rescue ArgumentError # binary / invalid encoding
    []
  end

  it "finds no %XX relax outside the two mandatory helpers" do
    files = scanned_globs.flat_map { |g| Pathname.glob(wagon_root.join(g)) }
      .reject { |p| allowed.include?(p.relative_path_from(wagon_root).to_s) }

    expect(files).not_to be_empty, "guard scanned nothing -- check WAGON_ROOT/globs"

    offenders = files.flat_map { |p| offending_lines(p, wagon_root) }
    expect(offenders).to be_empty, <<~MSG
      Percent-escape replacement found outside the mandatory helpers:

        #{offenders.join("\n  ")}

      This is forbidden by doc/url_encoding.md §6: relaxing %XX is safe ONLY on
      the immediate output of a percent-encoder. Use RelaxedUrlQuery.to_query
      (Ruby) or window.wsjrdpRelaxedQuery (JS) instead. Adding a file to ALLOWED
      is itself a policy change -- see doc/url_encoding.md §6.1.
    MSG
  end

  # Guard the guard: a regex that no longer matches the real pattern would pass
  # silently forever.
  it "detects the forbidden pattern in representative samples" do
    samples = [
      'url.gsub("%2C", ",")',
      "qs.replace(/%7E/gi, '~')",
      'str.sub("%2c", ",")',
      "x.gsub!(/%2C/, ',')"
    ]
    expect(samples.select { |s| s.match?(relax_call) }).to eq(samples)
  end

  it "does not flag comments or unrelated replacements" do
    benign = [
      "# decode %2C back to a comma",
      '// .replace(/%2C/gi, ",") -- described in a comment',
      'value.gsub("foo", "bar")',
      'text.gsub(/\s+/, " ")'
    ]
    expect(benign.reject { |s| s.match?(comment) }.select { |s| s.match?(relax_call) }).to be_empty
  end

  it "keeps the allowlist minimal and pointing at existing files" do
    expect(allowed.size).to eq(2)
    allowed.each { |rel| expect(wagon_root.join(rel)).to exist }
  end
end
