#!/usr/bin/env ruby
# frozen_string_literal: true

require "base64"
require "json"
require "net/http"
require "openssl"
require "optparse"
require "time"
require "uri"

module TestFlightGroupDistributor
  API_BASE = "https://api.appstoreconnect.apple.com/v1"

  class Error < StandardError; end

  class Client
    def initialize(key_id:, issuer_id:, key_path:)
      @key_id = key_id
      @issuer_id = issuer_id
      @private_key = OpenSSL::PKey.read(File.binread(key_path))
      @token = nil
      @token_expires_at = Time.at(0)
    end

    def get(path, params = {})
      request(:get, path, params: params)
    end

    def post(path, body)
      request(:post, path, body: body)
    end

    private

    def request(method, path, params: {}, body: nil)
      uri = URI("#{API_BASE}#{path}")
      uri.query = URI.encode_www_form(params) unless params.empty?
      request_class = method == :get ? Net::HTTP::Get : Net::HTTP::Post
      request = request_class.new(uri)
      request["Authorization"] = "Bearer #{token}"
      request["Accept"] = "application/json"
      unless body.nil?
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(body)
      end

      response = Net::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: true,
        open_timeout: 20,
        read_timeout: 60
      ) { |http| http.request(request) }
      status = response.code.to_i
      payload = response.body.to_s.empty? ? {} : JSON.parse(response.body)

      unless status.between?(200, 299)
        details = Array(payload["errors"]).map do |error|
          [error["code"], error["title"], error["detail"]].compact.join(": ")
        end
        raise Error, "App Store Connect #{method.to_s.upcase} #{path} returned #{status}: #{details.join('; ')}"
      end
      payload
    rescue JSON::ParserError => error
      raise Error, "App Store Connect returned invalid JSON: #{error.message}"
    end

    def token
      return @token if Time.now < @token_expires_at - 60

      issued_at = Time.now.to_i
      header = { "alg" => "ES256", "kid" => @key_id, "typ" => "JWT" }
      claims = {
        "iss" => @issuer_id,
        "iat" => issued_at,
        "exp" => issued_at + 1_200,
        "aud" => "appstoreconnect-v1"
      }
      signing_input = "#{base64url(JSON.generate(header))}.#{base64url(JSON.generate(claims))}"
      sequence = OpenSSL::ASN1.decode(@private_key.sign(OpenSSL::Digest::SHA256.new, signing_input))
      signature = sequence.value.map { |integer| integer_bytes(integer.value, 32) }.join
      @token = "#{signing_input}.#{base64url(signature)}"
      @token_expires_at = Time.at(issued_at + 1_200)
      @token
    end

    def integer_bytes(integer, length)
      hex = integer.to_i.to_s(16)
      hex = "0#{hex}" if hex.length.odd?
      bytes = [hex].pack("H*")
      raise Error, "invalid ES256 signature" if bytes.bytesize > length

      ("\x00" * (length - bytes.bytesize)) + bytes
    end

    def base64url(value)
      Base64.urlsafe_encode64(value, padding: false)
    end
  end

  class Runner
    SUBMITTED_REVIEW_STATES = %w[WAITING_FOR_REVIEW IN_REVIEW APPROVED].freeze
    EXTERNAL_SUBMITTED_STATES = %w[
      WAITING_FOR_BETA_REVIEW
      IN_BETA_REVIEW
      BETA_APPROVED
      IN_BETA_TESTING
    ].freeze
    TERMINAL_INTERNAL_STATES = %w[PROCESSING_EXCEPTION EXPIRED].freeze
    TERMINAL_EXTERNAL_STATES = %w[PROCESSING_EXCEPTION BETA_REJECTED EXPIRED].freeze

    def initialize(
      client:,
      app_id:,
      build_number:,
      platform:,
      internal_group:,
      external_group:,
      wait_seconds:,
      distribution_wait_seconds: 300
    )
      @client = client
      @app_id = app_id
      @build_number = build_number
      @platform = platform
      @internal_group = internal_group
      @external_group = external_group
      @wait_seconds = wait_seconds
      @distribution_wait_seconds = distribution_wait_seconds
    end

    def run
      build = wait_for_build
      build_id = build.fetch("id")
      groups = @client.get("/apps/#{@app_id}/betaGroups", "limit" => "200").fetch("data")
      assign(build_id, find_group(groups, @internal_group, true))
      assign(build_id, find_group(groups, @external_group, false))
      submit_external_review(build_id)
      internal_state, external_state = wait_for_distribution(build_id)
      puts "Verified #{platform_name} build #{@build_number}: " \
           "Internal is #{internal_state}; External is #{external_state}."
    end

    private

    def wait_for_build
      deadline = Time.now + @wait_seconds
      loop do
        response = @client.get(
          "/builds",
          "filter[app]" => @app_id,
          "filter[version]" => @build_number,
          "sort" => "-uploadedDate",
          "limit" => "10"
        )
        builds = response.fetch("data").select do |candidate|
          build_platform(candidate.fetch("id")) == @platform
        end
        raise Error, "multiple App Store builds use number #{@build_number}" if builds.length > 1

        build = builds.first
        return build if build&.dig("attributes", "processingState") == "VALID"

        state = build&.dig("attributes", "processingState") || "not visible"
        raise Error, "build #{@build_number} entered terminal state #{state}" if %w[FAILED INVALID].include?(state)
        raise Error, "build #{@build_number} was not valid after #{@wait_seconds} seconds" if Time.now >= deadline

        puts "Waiting for App Store build #{@build_number} (#{state})..."
        sleep 45
      end
    end

    def build_platform(build_id)
      @client.get("/builds/#{build_id}/preReleaseVersion").dig("data", "attributes", "platform")
    end

    def platform_name
      { "IOS" => "iOS", "MAC_OS" => "macOS" }.fetch(@platform, @platform)
    end

    def find_group(groups, name, internal)
      matches = groups.select do |group|
        group.dig("attributes", "name") == name &&
          group.dig("attributes", "isInternalGroup") == internal
      end
      raise Error, "TestFlight group #{name.inspect} was not found" if matches.empty?
      raise Error, "TestFlight group #{name.inspect} is ambiguous" if matches.length > 1

      matches.first
    end

    def assign(build_id, group)
      if group.dig("attributes", "hasAccessToAllBuilds")
        puts "#{group.dig('attributes', 'name')}: automatic access to all builds"
        return :automatic
      end

      @client.post(
        "/betaGroups/#{group.fetch('id')}/relationships/builds",
        "data" => [{ "type" => "builds", "id" => build_id }]
      )
      puts "#{group.dig('attributes', 'name')}: assigned"
      :assigned
    end

    def submit_external_review(build_id)
      submissions = @client.get(
        "/betaAppReviewSubmissions",
        "filter[build]" => build_id,
        "limit" => "10"
      ).fetch("data")
      active_submission = submissions.find do |submission|
        SUBMITTED_REVIEW_STATES.include?(submission.dig("attributes", "betaReviewState"))
      end
      if active_submission
        state = active_submission.dig("attributes", "betaReviewState")
        puts "External: Beta App Review already #{state}"
        return state
      end

      rejected_submission = submissions.find do |submission|
        submission.dig("attributes", "betaReviewState") == "REJECTED"
      end
      if rejected_submission
        raise Error, "build #{@build_number} has a rejected Beta App Review submission"
      end

      response = @client.post(
        "/betaAppReviewSubmissions",
        "data" => {
          "type" => "betaAppReviewSubmissions",
          "relationships" => {
            "build" => {
              "data" => { "type" => "builds", "id" => build_id }
            }
          }
        }
      )
      state = response.dig("data", "attributes", "betaReviewState")
      unless SUBMITTED_REVIEW_STATES.include?(state)
        raise Error, "Beta App Review submission returned unexpected state #{state || 'missing'}"
      end

      puts "External: submitted to Beta App Review (#{state})"
      state
    end

    def wait_for_distribution(build_id)
      deadline = Time.now + @distribution_wait_seconds
      loop do
        attributes = @client.get(
          "/builds/#{build_id}/buildBetaDetail"
        ).fetch("data").fetch("attributes")
        internal_state = attributes.fetch("internalBuildState")
        external_state = attributes.fetch("externalBuildState")
        if internal_state == "IN_BETA_TESTING" && EXTERNAL_SUBMITTED_STATES.include?(external_state)
          return [internal_state, external_state]
        end
        if TERMINAL_INTERNAL_STATES.include?(internal_state) ||
           TERMINAL_EXTERNAL_STATES.include?(external_state)
          raise Error, "build #{@build_number} entered terminal TestFlight state " \
                       "Internal=#{internal_state}, External=#{external_state}"
        end
        if Time.now >= deadline
          raise Error, "build #{@build_number} did not reach both TestFlight groups after " \
                       "#{@distribution_wait_seconds} seconds: " \
                       "Internal=#{internal_state}, External=#{external_state}"
        end

        puts "Waiting for TestFlight distribution " \
             "(Internal=#{internal_state}, External=#{external_state})..."
        sleep 15
      end
    end
  end

end

if $PROGRAM_NAME == __FILE__
  options = {
    app_id: "6783830742",
    platform: "MAC_OS",
    internal_group: "Internal",
    external_group: "External",
    wait_seconds: 2_700,
    distribution_wait_seconds: 300
  }
  OptionParser.new do |parser|
    parser.on("--key-id VALUE") { |value| options[:key_id] = value }
    parser.on("--issuer-id VALUE") { |value| options[:issuer_id] = value }
    parser.on("--key-path VALUE") { |value| options[:key_path] = value }
    parser.on("--app-id VALUE") { |value| options[:app_id] = value }
    parser.on("--build-number VALUE") { |value| options[:build_number] = value }
    parser.on("--platform VALUE") { |value| options[:platform] = value }
    parser.on("--internal-group VALUE") { |value| options[:internal_group] = value }
    parser.on("--external-group VALUE") { |value| options[:external_group] = value }
    parser.on("--wait-seconds VALUE", Integer) { |value| options[:wait_seconds] = value }
    parser.on("--distribution-wait-seconds VALUE", Integer) do |value|
      options[:distribution_wait_seconds] = value
    end
  end.parse!

  required = %i[key_id issuer_id key_path app_id build_number platform internal_group external_group]
  missing = required.select { |key| options[key].to_s.empty? }
  raise TestFlightGroupDistributor::Error, "missing options: #{missing.join(', ')}" unless missing.empty?
  raise TestFlightGroupDistributor::Error, "build number must be numeric" unless options[:build_number].match?(/\A\d+\z/)

  client = TestFlightGroupDistributor::Client.new(
    key_id: options[:key_id],
    issuer_id: options[:issuer_id],
    key_path: options[:key_path]
  )
  TestFlightGroupDistributor::Runner.new(
    client: client,
    app_id: options[:app_id],
    build_number: options[:build_number],
    platform: options[:platform],
    internal_group: options[:internal_group],
    external_group: options[:external_group],
    wait_seconds: options[:wait_seconds],
    distribution_wait_seconds: options[:distribution_wait_seconds]
  ).run
end
