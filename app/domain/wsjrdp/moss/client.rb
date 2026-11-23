# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp::Moss
  # Reads from the Moss API with the credentials handed in.
  #
  #   client = Wsjrdp::Moss::Client.new(base_url: …, client_id: …, client_secret: …, scope: "read")
  #   client.all("v1/users")                # every user, page after page, as hashes
  #   client.each("v1/teams").first(3)      # the same, lazily
  #
  # Renews its token before it runs out or after a 401, tries a read again
  # when Moss is busy or silent, and keeps every request and answer in
  # #transcript, secrets cut out. Raises Wsjrdp::Moss::Error.
  class Client
    PAGE_SIZE = 100
    # Guards against a list that never says it is complete.
    MAX_PAGES = 1000
    # A token this close to running out is renewed first.
    TOKEN_MARGIN = 300
    # Tried again RETRIES times, after Retry-After (at most MAX_WAIT) or 1, 2 s.
    RETRY_STATUSES = [429, 502, 503, 504].freeze
    RETRIES = 2
    MAX_WAIT = 10

    attr_reader :transcript

    def initialize(base_url:, client_id:, client_secret:, scope: nil,
      clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }, sleeper: ->(seconds) { sleep(seconds) })
      @base_url = base_url.to_s.chomp("/")
      @client_secret = client_secret
      @clock = clock
      @sleeper = sleeper
      @transcript = Transcript.new(clock: clock)
      @total_items = {}
      @token_request = TokenRequest.new(base_url: @base_url, client_id: client_id, client_secret: client_secret,
        scope: scope, transcript: @transcript)
    end

    def inspect = "#<#{self.class.name} #{@base_url}>"
    alias_method :to_s, :inspect

    # The body of one GET as a Hash.
    def get(path, params = {})
      response = with_retries { send_get(path, params, token) }
      if response.status == 401
        @token = nil
        response = with_retries { send_get(path, params, token) }
      end
      raise Error.from_response(response, secrets: secrets) unless response.success?

      Wsjrdp::Moss.json_object(response.body)
    end

    # Every record of a list (its "data"), page after page, until Moss says
    # there are no more. Moss pages by offset, so a record may repeat and
    # another be skipped; compare with #total_items.
    def each(path, params = {}, page_size: PAGE_SIZE)
      return enum_for(:each, path, params, page_size: page_size) unless block_given?

      page = 0
      loop do
        raise Error, "more than #{MAX_PAGES} pages of #{path}" if (page += 1) > MAX_PAGES

        body = get(path, params.merge(page: page, page_size: page_size))
        @total_items[path] = body.dig("meta", "pagination", "totalItems")
        Array(body["data"]).each { |record| yield record }
        break unless body.dig("meta", "pagination", "hasMore")
      end
    end

    def all(path, params = {}, page_size: PAGE_SIZE) = each(path, params, page_size: page_size).to_a

    # How many records Moss said the list has; nil when it did not say.
    def total_items(path) = @total_items[path]

    private

    def token
      if @token.nil? || @clock.call >= @token_expires_at
        @token = @token_request.call
        @transcript.add_secret(@token.access_token)
        lifetime = @token.expires_in.is_a?(Integer) ? [@token.expires_in - TOKEN_MARGIN, 0].max : Float::INFINITY
        @token_expires_at = @clock.call + lifetime
      end
      @token
    end

    def send_get(path, params, token)
      url = "#{@base_url}/#{path}#{"?#{params.to_query}" if params.present?}"
      @transcript.run(:read, method: "GET", url: url) do
        Wsjrdp::Moss.connection(@base_url).get(path, params) do |request|
          request.headers["Authorization"] = "Bearer #{token.access_token}"
          request.headers["Accept"] = "application/json"
        end
      end
    end

    def secrets = [@client_secret, @token&.access_token]

    def with_retries
      (0..RETRIES).each do |attempt|
        response = yield
        return response unless RETRY_STATUSES.include?(response.status) && attempt < RETRIES

        @sleeper.call(wait(response.headers["Retry-After"], attempt))
      rescue Error => e
        raise unless e.status.nil? && attempt < RETRIES

        @sleeper.call(wait(nil, attempt))
      end
    end

    def wait(retry_after, attempt) = (retry_after.to_s.match?(/\A\d+\z/) ? retry_after.to_i : attempt + 1).clamp(0, MAX_WAIT)
  end
end
