# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Store for tiny UI-chrome values the BROWSER may change without a request: the
# widget writes `document.cookie` directly (the cookie name travels to the JS as
# a data- attribute), and the controller reads it back on the next render through
# the same resolver and allow-list as any other input. One cookie per field, so
# the JS can set exactly one value.
#
# CAVEAT (D2d) -- :cookie means the value does NOT always travel through a
# request (the browser changes it on its own; the server only learns about it on
# the next render) and a cookie is client-controlled (editable in the browser).
# Never choose :cookie for anything sensitive, for anything that influences the
# row set or the scope, or wherever the controller's primacy over the value
# matters. It is for pure display chrome -- the filter pane's open/closed state
# is the only use today. Only SINGLE-TOKEN values are accepted; anything else is
# ignored on read and refused on write. Use it only for tables with a STATIC
# store key: unlike the session store it has no key cap, so a per-row nested
# table would mint one cookie per opened row.
#
# Same D7 semantics as the session store: `write` REPLACES the table's cookies
# (a field missing from the hash is forgotten, an empty hash removes them all),
# and a table's cookies are exactly `<prefix><short>` -- a sibling table whose
# key extends this key (e.g. `…|bk`) is never touched by read/write/delete.
class Wsjrdp::TableStateStore::Cookie
  NAME_PREFIX = "wsjrdp_ts_"
  VALUE_FORMAT = /\A[A-Za-z0-9_-]{1,16}\z/
  SHORT_FORMAT = /\A[a-z0-9]+\z/ # one field name, never a sanitised sub-key
  MAX_AGE = 31_536_000 # one year, in seconds

  # The cookie one field of one table lives in. Also used by the view, which
  # hands the name to the pane JS (Wsjrdp::TableState#cookie_name).
  def self.cookie_name(store_key, short)
    "#{NAME_PREFIX}#{sanitize(store_key)}_#{short}"
  end

  def self.sanitize(store_key)
    store_key.to_s.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, "")
  end

  def initialize(cookies)
    @cookies = cookies
  end

  def read(key)
    own_cookies(key).to_h { |name, value| [short_of(key, name), value] }
      .select { |_short, value| VALUE_FORMAT.match?(value) }
  end

  # Replaces the table's cookies: sets the wanted ones (skipping unchanged
  # values -- the browser usually wrote them already, and an unchanged cookie
  # needs no Set-Cookie header) and deletes every other cookie of this key.
  def write(key, hash)
    wanted = hash.to_h { |short, value| [self.class.cookie_name(key, short), value.to_s] }
      .select { |_name, value| VALUE_FORMAT.match?(value) }
    own_cookies(key).each_key { |name| @cookies.delete(name, path: "/") unless wanted.key?(name) }
    wanted.each do |name, value|
      next if @cookies[name].to_s == value
      @cookies[name] = {value: value, path: "/", expires: MAX_AGE.seconds}
    end
  end

  def delete(key)
    own_cookies(key).each_key { |name| @cookies.delete(name, path: "/") }
  end

  def delete_all(key_prefix)
    scan("#{NAME_PREFIX}#{self.class.sanitize(key_prefix)}").each_key { |name| @cookies.delete(name, path: "/") }
  end

  private

  # The cookies of exactly this key: `<key prefix><short>` where the short is a
  # single field name. A sibling key that extends this one sanitises to
  # `<key prefix>bk_e` -- its remainder carries a "_" and is excluded.
  def own_cookies(key)
    prefix = self.class.cookie_name(key, "")
    scan(prefix).select { |name, _value| SHORT_FORMAT.match?(name.delete_prefix(prefix)) }
  end

  def short_of(key, name)
    name.delete_prefix(self.class.cookie_name(key, ""))
  end

  def scan(name_prefix)
    @cookies.to_h.filter_map { |name, value|
      [name.to_s, value.to_s] if name.to_s.start_with?(name_prefix)
    }.to_h
  end
end
