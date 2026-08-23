//  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
//
//  This file is part of hitobito_wsjrdp_2027 and licensed under the
//  Affero General Public License version 3 or later. See the COPYING
//  file at the top-level directory or at
//  https://github.com/smeky42/hitobito_wsjrdp_2027

// Tests for window.wsjrdpRelaxedQuery (doc/url_encoding.md §6). The
// implementation lives INSIDE app/views/shared/_relaxed_query_js.html.haml (a
// :javascript filter block); this test extracts the code between its
// wsjrdp-relaxed-query-begin/end markers and runs it against a fresh fake
// `window`, so partial and test cannot drift apart silently.
//
// Run (no dependencies, built-in runner), from the wagon root:
//   node --test "spec/javascripts/**/*.test.mjs"
// (Quote the glob so node expands it. A bare directory argument does not work.)

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const PARTIAL = join(dirname(fileURLToPath(import.meta.url)),
  "../../app/views/shared/_relaxed_query_js.html.haml");

function loadHelper() {
  const source = readFileSync(PARTIAL, "utf8");
  const match = source.match(
    /\/\/ wsjrdp-relaxed-query-begin\n([\s\S]*?)\/\/ wsjrdp-relaxed-query-end/
  );
  assert.ok(match, "marker comments not found in _relaxed_query_js.html.haml");
  const window = {};
  new Function("window", match[1])(window);
  assert.ok(window.wsjrdpRelaxedQuery, "helper did not install itself");
  return window.wsjrdpRelaxedQuery;
}

const helper = loadHelper();

// Parse a query string back the way our stack does (URLSearchParams splits on
// "&" / "=", percent-decodes, "+" -> space -- same as Rack for these cases).
const parseBack = (qs) => new URLSearchParams(qs);

// ---------------------------------------------------------------- readability

test("keeps , and ~ literal in values", () => {
  const qs = helper.serialize(new URLSearchParams({ sort: "bez,nr~" }));
  assert.equal(qs, "sort=bez,nr~");
});

test("keeps , and ~ literal across several params (sort + cols)", () => {
  const sp = new URLSearchParams();
  sp.set("sort", "bez~,cnt~");
  sp.set("cols", "nr,bez,~st,sum,cnt");
  const qs = helper.serialize(sp);
  assert.equal(qs, "sort=bez~,cnt~&cols=nr,bez,~st,sum,cnt");
  assert.ok(!/%2C|%7E/i.test(qs));
});

test("empty params serialize to the empty string", () => {
  assert.equal(helper.serialize(new URLSearchParams()), "");
});

// ---------------------------------------------------- round-trip (the security property)

const ROUNDTRIP_VALUES = [
  "hello",
  "a,b,c",
  "x~y~",
  "100%",
  "%",
  "%2C",            // encoded comma as DATA -- must survive as the 3-char text
  "%7E",
  "%2c%7e",
  "%252C",          // double encoded
  "a&b=c",
  "a=b",
  "1+1=2",
  "a#frag",
  "a b",
  "a;b",
  "a?b",
  "!$&'()*+,;=",    // all sub-delims
  ":/?#[]@",        // gen-delims
  "Zäune, Bäume & Käfer ~ 100%",
  "🏕️,~%",
  "a\nb\tc",
  "x%26evil%3D1"    // injection attempt -- must NOT become a new param
];

for (const value of ROUNDTRIP_VALUES) {
  test(`round-trips ${JSON.stringify(value)}`, () => {
    const qs = helper.serialize(new URLSearchParams({ v: value }));
    assert.equal(parseBack(qs).get("v"), value);
  });
}

test("round-trips keys containing , ~ % & =", () => {
  const sp = new URLSearchParams();
  for (const [k, v] of [["a,b", "1"], ["c~d", "2"], ["e%f", "3"], ["g&h", "4"], ["i=j", "5"]]) {
    sp.set(k, v);
  }
  const parsed = parseBack(helper.serialize(sp));
  assert.deepEqual([...parsed.entries()],
    [["a,b", "1"], ["c~d", "2"], ["e%f", "3"], ["g&h", "4"], ["i=j", "5"]]);
});

test("never splits off a forged parameter from hostile values", () => {
  const parsed = parseBack(helper.serialize(new URLSearchParams({ q: "evil=1&admin=true" })));
  assert.deepEqual([...parsed.keys()], ["q"]);
  assert.equal(parsed.get("q"), "evil=1&admin=true");
});

test("round-trips repeated params (arrays)", () => {
  const sp = new URLSearchParams();
  for (const v of ["a,1", "b~2", "100%"]) sp.append("account_number[]", v);
  const parsed = parseBack(helper.serialize(sp));
  assert.deepEqual(parsed.getAll("account_number[]"), ["a,1", "b~2", "100%"]);
});

test("accepts FormData", () => {
  const fd = new FormData();
  fd.append("sort", "bez,nr~");
  fd.append("q", "100% & more");
  const qs = helper.serialize(fd);
  const parsed = parseBack(qs);
  assert.equal(parsed.get("sort"), "bez,nr~");
  assert.equal(parsed.get("q"), "100% & more");
  assert.ok(qs.includes("sort=bez,nr~"));
});

// --------------------------------------------------------- deterministic fuzz

function mulberry32(seed) {
  return function () {
    seed |= 0; seed = (seed + 0x6D2B79F5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

test("round-trips 500 fuzzed adversarial values byte-identically", () => {
  const charset = ["a", "b", "c", "0", "9", "%", ",", "~", "&", "=", "+", "#",
    " ", ";", "'", "(", ")", "*", "!", "$", "[", "]", "ü", "€", "\\", '"'];
  const rand = mulberry32(20260823); // fixed seed -> reproducible failures
  for (let i = 0; i < 500; i++) {
    const len = Math.floor(rand() * 25);
    let value = "";
    for (let j = 0; j < len; j++) value += charset[Math.floor(rand() * charset.length)];
    const qs = helper.serialize(new URLSearchParams({ v: value }));
    assert.equal(parseBack(qs).get("v"), value, `fuzz #${i} failed for ${JSON.stringify(value)}`);
  }
});

// ------------------------------------------------------------- href assembly

test("href assembles path + relaxed query + hash", () => {
  const url = new URL("http://x.test/bookkeeping/cost_centers?sort=bez%2Ccnt%7E&per=all#frag");
  assert.equal(helper.href(url), "/bookkeeping/cost_centers?sort=bez,cnt~&per=all#frag");
});

test("href omits the ? when the query is empty", () => {
  assert.equal(helper.href(new URL("http://x.test/foo")), "/foo");
});

test("href never touches path or fragment octets", () => {
  const url = new URL("http://x.test/pa%2Cth/x?open=1%2C2#a%2Cb");
  const result = helper.href(url);
  assert.ok(result.startsWith("/pa%2Cth/x?"), "path must stay encoded");
  assert.ok(result.endsWith("#a%2Cb"), "fragment must stay as-is");
  assert.ok(result.includes("open=1,2"), "query must be relaxed");
});

// A pathname beginning with "//" would make the result a protocol-relative
// (network-path) reference resolving to another origin -- an open redirect.
test("href never returns a protocol-relative reference", () => {
  for (const raw of ["http://app.test//evil.example/x?a=1",
    "http://app.test///evil.example/x",
    "http://app.test//evil.example"]) {
    const url = new URL(raw);
    assert.ok(url.pathname.startsWith("//"), `precondition: ${raw} has // pathname`);
    const result = helper.href(url);
    assert.ok(!result.startsWith("//"), `must not be protocol-relative: ${result}`);
    assert.ok(result.startsWith("/"), `must stay origin-relative: ${result}`);
    // resolves back to our own origin, not the injected one
    assert.equal(new URL(result, "http://app.test").origin, "http://app.test");
  }
});

test("href leaves ordinary single-slash paths untouched", () => {
  const url = new URL("http://app.test/bookkeeping/suppliers?sort=bez%2Cnr%7E");
  assert.equal(helper.href(url), "/bookkeeping/suppliers?sort=bez,nr~");
});

// ------------------------------------------- encapsulation (API contract)

test("serialize throws on plain strings (raw-string relax is forbidden)", () => {
  assert.throws(() => helper.serialize("sort=bez%2Cnr"), TypeError);
});

test("serialize throws on null / undefined / objects", () => {
  for (const bad of [null, undefined, 42, { sort: "x" }, ["a", "b"]]) {
    assert.throws(() => helper.serialize(bad), TypeError, `should throw for ${String(bad)}`);
  }
});

test("href throws on non-URL input", () => {
  assert.throws(() => helper.href("/foo?a=1"), TypeError);
  assert.throws(() => helper.href({ pathname: "/x", searchParams: new URLSearchParams(), hash: "" }), TypeError);
});

test("exposes exactly serialize and href", () => {
  assert.deepEqual(Object.keys(helper).sort(), ["href", "serialize"]);
});
