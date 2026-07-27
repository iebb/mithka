#!/usr/bin/env ruby
# frozen_string_literal: true

# Prepares and optionally submits one exact Mithka iOS build to App Store
# review. The script is dry-run-only unless --apply is supplied. It resolves
# the App Store build through either an exact Xcode Cloud build run or a
# checksum-pinned uploaded IPA. It verifies build identity, processing state,
# and distribution audience before writing anything.

require "base64"
require "digest"
require "json"
require "net/http"
require "open3"
require "openssl"
require "optparse"
require "time"
require "uri"

module MithkaAppStoreRelease
  API_BASE = "https://api.appstoreconnect.apple.com/v1"
  DEFAULT_APP_ID = "6783830742"
  DEFAULT_KEY_ID = "BJYTRDQ86C"
  DEFAULT_RELEASE_NOTES = {
    "en-US" => "Enjoy a redesigned video player with clearer controls, scrubbing previews, picture-in-picture, and more reliable first playback. This release also improves desktop and tablet layouts, image previews, chat performance, themes, and localization.",
    "zh-Hans" => "全新视频播放器带来更清晰的操作、进度预览、画中画与更可靠的首次播放。本版本还改进了桌面端和平板布局、图片预览、聊天性能、主题与本地化。"
  }.freeze
  REVIEWABLE_VERSION_STATES = %w[
    DEVELOPER_REJECTED
    INVALID_BINARY
    METADATA_REJECTED
    PREPARE_FOR_SUBMISSION
    READY_FOR_REVIEW
    REJECTED
  ].freeze
  SUBMITTED_VERSION_STATES = %w[
    IN_REVIEW
    PENDING_APPLE_RELEASE
    PENDING_DEVELOPER_RELEASE
    PROCESSING_FOR_DISTRIBUTION
    READY_FOR_DISTRIBUTION
    READY_FOR_SALE
    WAITING_FOR_REVIEW
  ].freeze
  SUBMITTED_REVIEW_STATES = %w[
    COMPLETE
    IN_REVIEW
    WAITING_FOR_REVIEW
  ].freeze

  class Error < StandardError; end

  class ApiError < Error
    attr_reader :status

    def initialize(status, method, path, payload)
      @status = status
      messages = Array(payload && payload["errors"]).flat_map do |error|
        primary = [error["code"], error["title"], error["detail"]].compact.join(": ")
        associated = (error.dig("meta", "associatedErrors") || {}).values.flatten.map do |associated_error|
          [associated_error["code"], associated_error["title"], associated_error["detail"]].compact.join(": ")
        end
        [primary, *associated]
      end
      detail = messages.empty? ? "unexpected response" : messages.join("; ")
      super("App Store Connect #{method.to_s.upcase} #{path} returned #{status}: #{detail}")
    end
  end

  class Client
    def initialize(key_id:, issuer_id:, key_path:, base_url: API_BASE)
      @key_id = key_id
      @issuer_id = issuer_id
      @private_key = OpenSSL::PKey.read(File.binread(key_path))
      @base_url = base_url.sub(%r{/+\z}, "")
      @token = nil
      @token_expires_at = Time.at(0)
    end

    def get(path, params = {})
      request(:get, path, params: params)
    end

    def post(path, body)
      request(:post, path, body: body)
    end

    def patch(path, body)
      request(:patch, path, body: body)
    end

    private

    def request(method, path, params: {}, body: nil)
      uri = URI.parse("#{@base_url}#{path}")
      uri.query = URI.encode_www_form(params) unless params.empty?
      request_class = {
        get: Net::HTTP::Get,
        post: Net::HTTP::Post,
        patch: Net::HTTP::Patch
      }.fetch(method)
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
        use_ssl: uri.scheme == "https",
        open_timeout: 20,
        read_timeout: 45
      ) { |http| http.request(request) }
      payload = response.body.to_s.empty? ? {} : JSON.parse(response.body)
      status = response.code.to_i
      raise ApiError.new(status, method, path, payload) unless status.between?(200, 299)

      payload
    rescue JSON::ParserError => error
      raise Error, "App Store Connect returned invalid JSON for #{method.to_s.upcase} #{path}: #{error.message}"
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
      der_signature = @private_key.sign(OpenSSL::Digest::SHA256.new, signing_input)
      sequence = OpenSSL::ASN1.decode(der_signature)
      signature = sequence.value.map { |integer| integer_to_bytes(integer.value, 32) }.join
      @token = "#{signing_input}.#{base64url(signature)}"
      @token_expires_at = Time.at(issued_at + 1_200)
      @token
    end

    def integer_to_bytes(integer, length)
      hex = integer.to_i.to_s(16)
      hex = "0#{hex}" if hex.length.odd?
      bytes = [hex].pack("H*")
      raise Error, "ES256 signature component is longer than #{length} bytes" if bytes.bytesize > length

      ("\x00" * (length - bytes.bytesize)) + bytes
    end

    def base64url(value)
      Base64.urlsafe_encode64(value, padding: false)
    end
  end

  class Runner
    VERSION_METADATA_KEYS = %w[
      description
      keywords
      marketingUrl
      promotionalText
      supportUrl
    ].freeze
    REVIEW_DETAIL_KEYS = %w[
      contactEmail
      contactFirstName
      contactLastName
      contactPhone
      demoAccountName
      demoAccountPassword
      demoAccountRequired
      notes
    ].freeze

    attr_reader :resolved_build_id

    def initialize(client:, app_id:, version:, binary_version:, build_number:, source_commit:,
                   release_notes:, apply:, submit:, ci_build_run_id: nil,
                   uploaded_build_id: nil, artifact_path: nil, artifact_sha256: nil,
                   wait_seconds: 0, out: $stdout, sleeper: Kernel)
      @client = client
      @app_id = app_id
      @version = version
      @binary_version = binary_version
      @build_number = build_number.to_s
      @ci_build_run_id = ci_build_run_id
      @uploaded_build_id = uploaded_build_id
      @artifact_path = artifact_path
      @artifact_sha256 = artifact_sha256&.downcase
      @source_commit = source_commit.downcase
      @release_notes = release_notes
      @apply = apply
      @submit = submit
      @wait_seconds = wait_seconds
      @out = out
      @sleeper = sleeper
      validate_options!
    end

    def run
      release_notes = validate_release_notes(@release_notes)
      build = resolve_exact_build
      @resolved_build_id = build.fetch("id")
      version = find_version

      if version.nil? && !@apply
        validate_copy_sources(release_notes)
        log("PLAN create iOS App Store version #{@version} with release type AFTER_APPROVAL")
        log("PLAN attach build #{@build_number} (#{@resolved_build_id})")
        log_metadata_plan(release_notes)
        log("PLAN verify App Review contact and demo-account details")
        log("PLAN submit through reviewSubmissions") if @submit
        log("DRY RUN complete; no App Store Connect state was changed")
        return
      end

      version ||= create_version
      ensure_version_can_be_used!(version)
      version_id = version.fetch("id")
      ensure_build_attached(version_id, @resolved_build_id)
      sync_version_metadata(version_id, release_notes)
      ensure_review_detail(version_id)
      submission = ensure_submission(version_id) if @submit
      unless @apply
        log("DRY RUN complete; no App Store Connect state was changed")
        return
      end
      verify(version_id, @resolved_build_id, release_notes, submission)
      log("App Store release preparation verified")
    end

    private

    def validate_options!
      raise Error, "--version must be a dotted numeric version" unless @version.match?(/\A\d+(?:\.\d+){1,2}\z/)
      raise Error, "--binary-version must be a dotted numeric version" unless @binary_version.match?(/\A\d+(?:\.\d+){1,2}\z/)
      raise Error, "--build-number must be numeric" unless @build_number.match?(/\A\d+\z/)
      raise Error, "--source-commit must be the full 40-character SHA" unless @source_commit.match?(/\A[0-9a-f]{40}\z/)
      raise Error, "--wait-seconds cannot be negative" if @wait_seconds.negative?
      upload_fields = [@uploaded_build_id, @artifact_path, @artifact_sha256]
      if upload_fields.any? { |value| !value.to_s.empty? } && upload_fields.any? { |value| value.to_s.empty? }
        raise Error, "--uploaded-build-id, --artifact-path, and --artifact-sha256 must be supplied together"
      end
      if upload_fields.all? { |value| !value.to_s.empty? }
        raise Error, "--uploaded-build-id must be a UUID" unless @uploaded_build_id.match?(/\A[0-9a-fA-F-]{36}\z/)
        raise Error, "artifact does not exist: #{@artifact_path}" unless File.file?(@artifact_path)
        raise Error, "--artifact-sha256 must be a full 64-character SHA-256" unless @artifact_sha256.match?(/\A[0-9a-f]{64}\z/)
        raise Error, "use either --ci-build-run-id or --uploaded-build-id, not both" if @ci_build_run_id
      elsif !@ci_build_run_id&.match?(/\A[0-9a-fA-F-]{36}\z/)
        raise Error, "--ci-build-run-id must be a UUID unless --uploaded-build-id is supplied"
      end
    end

    def validate_release_notes(release_notes)
      expected_locales = %w[en-US zh-Hans]
      missing = expected_locales - release_notes.keys
      extras = release_notes.keys - expected_locales
      raise Error, "release notes are missing locales: #{missing.join(', ')}" unless missing.empty?
      raise Error, "unsupported release-note locales: #{extras.join(', ')}" unless extras.empty?

      release_notes.transform_values do |notes|
        value = notes.to_s.strip
        raise Error, "release notes cannot be empty" if value.empty?
        raise Error, "release notes exceed 4,000 characters" if value.length > 4_000

        value
      end
    end

    def resolve_exact_build
      return resolve_exact_uploaded_build if @uploaded_build_id

      deadline = Time.now + @wait_seconds
      loop do
        run = @client.get("/ciBuildRuns/#{@ci_build_run_id}").fetch("data")
        attributes = run.fetch("attributes")
        actual_commit = attributes.dig("sourceCommit", "commitSha").to_s.downcase
        unless actual_commit == @source_commit
          raise Error, "Xcode Cloud run #{@ci_build_run_id} uses #{actual_commit.empty? ? 'no source commit' : actual_commit}, expected #{@source_commit}"
        end
        if attributes["executionProgress"] == "COMPLETE" && attributes["completionStatus"] != "SUCCEEDED"
          raise Error, "Xcode Cloud run #{@ci_build_run_id} completed with #{attributes['completionStatus']}"
        end

        builds = @client.get("/ciBuildRuns/#{@ci_build_run_id}/builds", "limit" => "200").fetch("data")
        matching_number = builds.select { |build| build.dig("attributes", "version").to_s == @build_number }
        if matching_number.length > 1
          raise Error, "Xcode Cloud run #{@ci_build_run_id} has multiple builds numbered #{@build_number}"
        end
        build = matching_number.first
        if build
          assert_build_identity!(build)
          state = build.dig("attributes", "processingState")
          if attributes["executionProgress"] == "COMPLETE" && attributes["completionStatus"] == "SUCCEEDED" && state == "VALID"
            log("Resolved Xcode Cloud run #{@ci_build_run_id} to binary #{@binary_version} (#{@build_number}), build #{build['id']}, source #{@source_commit}; listing version #{@version}")
            return build
          end
          raise Error, "App Store build #{@build_number} entered terminal state #{state}" if %w[FAILED INVALID].include?(state)
        end

        if Time.now >= deadline
          progress = attributes["executionProgress"]
          completion = attributes["completionStatus"] || "not complete"
          state = build&.dig("attributes", "processingState") || "not uploaded"
          raise Error, "exact build is not ready: Xcode Cloud #{progress}/#{completion}; App Store build #{state}"
        end
        log("Waiting for exact Xcode Cloud/App Store build (run #{attributes['executionProgress']}, build #{build&.dig('attributes', 'processingState') || 'not uploaded'})")
        @sleeper.sleep([30, [deadline - Time.now, 1].max].min)
      end
    end

    def resolve_exact_uploaded_build
      actual_sha256 = Digest::SHA256.file(@artifact_path).hexdigest
      unless actual_sha256 == @artifact_sha256
        raise Error, "artifact SHA-256 is #{actual_sha256}, expected #{@artifact_sha256}"
      end

      deadline = Time.now + @wait_seconds
      loop do
        build = @client.get("/builds/#{@uploaded_build_id}").fetch("data")
        actual_number = build.dig("attributes", "version").to_s
        unless actual_number == @build_number
          raise Error, "uploaded build #{@uploaded_build_id} is numbered #{actual_number}, expected #{@build_number}"
        end
        app = assert_build_identity!(build)
        expected_bundle_id = app.dig("attributes", "bundleId").to_s
        raise Error, "App Store app #{@app_id} has no bundle ID to verify against the uploaded artifact" if expected_bundle_id.empty?

        assert_uploaded_ipa_identity!(expected_bundle_id)
        state = build.dig("attributes", "processingState")
        if state == "VALID"
          log("Resolved uploaded artifact #{@artifact_path} (SHA-256 #{@artifact_sha256}) to binary #{@binary_version} (#{@build_number}), build #{build['id']}; declared source provenance #{@source_commit}, listing version #{@version}")
          return build
        end
        raise Error, "uploaded build #{@build_number} entered terminal state #{state}" if %w[FAILED INVALID].include?(state)
        if Time.now >= deadline
          raise Error, "exact uploaded build is not ready: App Store build #{state || 'not available'}"
        end

        log("Waiting for exact uploaded App Store build #{@build_number} (#{state || 'not available'})")
        @sleeper.sleep([30, [deadline - Time.now, 1].max].min)
      end
    end

    def assert_build_identity!(build)
      build_id = build.fetch("id")
      attributes = build.fetch("attributes")
      raise Error, "build #{build_id} is expired" if attributes["expired"]
      unless attributes["buildAudienceType"] == "APP_STORE_ELIGIBLE"
        raise Error, "build #{build_id} is not App Store eligible (#{attributes['buildAudienceType']})"
      end

      app = @client.get("/builds/#{build_id}/app").fetch("data")
      raise Error, "build #{build_id} belongs to app #{app['id']}, expected #{@app_id}" unless app.fetch("id") == @app_id

      prerelease = @client.get("/builds/#{build_id}/preReleaseVersion").fetch("data")
      marketing_version = prerelease.dig("attributes", "version").to_s
      unless marketing_version == @binary_version
        raise Error, "build #{build_id} has binary marketing version #{marketing_version}, expected #{@binary_version}"
      end

      app
    end

    def assert_uploaded_ipa_identity!(expected_bundle_id)
      entries = run_command!("unzip", "-Z1", @artifact_path).lines.map(&:strip)
      info_entries = entries.grep(%r{\APayload/[^/]+\.app/Info\.plist\z})
      unless info_entries.length == 1
        raise Error, "uploaded artifact must contain exactly one top-level app Info.plist; found #{info_entries.length}"
      end

      plist = run_command!("unzip", "-p", @artifact_path, info_entries.first)
      json = run_command!("plutil", "-convert", "json", "-o", "-", "--", "-", stdin_data: plist)
      info = JSON.parse(json)
      expected = {
        "CFBundleIdentifier" => expected_bundle_id,
        "CFBundleShortVersionString" => @binary_version,
        "CFBundleVersion" => @build_number
      }
      expected.each do |key, value|
        actual = info[key].to_s
        raise Error, "uploaded artifact #{key} is #{actual.inspect}, expected #{value.inspect}" unless actual == value
      end
    rescue JSON::ParserError => error
      raise Error, "uploaded artifact Info.plist is not valid JSON after conversion: #{error.message}"
    end

    def run_command!(*command, stdin_data: "")
      stdout, stderr, status = Open3.capture3(*command, stdin_data: stdin_data)
      return stdout if status.success?

      detail = stderr.to_s.strip
      detail = "exit #{status.exitstatus}" if detail.empty?
      raise Error, "#{command.first} failed while inspecting uploaded artifact: #{detail}"
    end

    def find_version
      versions = versions_for_string(@version)
      raise Error, "multiple iOS App Store versions exist for #{@version}" if versions.length > 1

      versions.first
    end

    def create_version
      log("CREATE iOS App Store version #{@version}")
      response = @client.post(
        "/appStoreVersions",
        {
          "data" => {
            "type" => "appStoreVersions",
            "attributes" => {
              "platform" => "IOS",
              "versionString" => @version,
              "releaseType" => "AFTER_APPROVAL"
            },
            "relationships" => {
              "app" => { "data" => { "type" => "apps", "id" => @app_id } }
            }
          }
        }
      )
      response.fetch("data")
    end

    def ensure_version_can_be_used!(version)
      state = version.dig("attributes", "appStoreState") || version.dig("attributes", "appVersionState")
      return if REVIEWABLE_VERSION_STATES.include?(state) || SUBMITTED_VERSION_STATES.include?(state)

      raise Error, "App Store version #{@version} is in unsupported state #{state}"
    end

    def ensure_build_attached(version_id, build_id)
      response = @client.get("/appStoreVersions/#{version_id}", "include" => "build")
      current_build_id = response.dig("data", "relationships", "build", "data", "id")
      return log("Build #{@build_number} is already attached") if current_build_id == build_id

      state = response.dig("data", "attributes", "appStoreState")
      if SUBMITTED_VERSION_STATES.include?(state)
        raise Error, "version #{@version} is already #{state} with a different build (#{current_build_id || 'none'})"
      end
      return log("PLAN attach build #{@build_number} (#{build_id})") unless @apply

      log("ATTACH build #{@build_number} (#{build_id})")
      @client.patch(
        "/appStoreVersions/#{version_id}",
        {
          "data" => {
            "type" => "appStoreVersions",
            "id" => version_id,
            "relationships" => {
              "build" => { "data" => { "type" => "builds", "id" => build_id } }
            }
          }
        }
      )
    end

    def sync_version_metadata(version_id, release_notes)
      response = @client.get(
        "/appStoreVersions/#{version_id}/appStoreVersionLocalizations",
        "limit" => "200"
      )
      existing = response.fetch("data").to_h { |item| [item.dig("attributes", "locale"), item] }
      source_by_locale = latest_sale_localizations(version_id)
      release_notes.each do |locale, notes|
        localization = existing[locale]
        if localization.nil?
          source = source_by_locale[locale]
          raise Error, "no prior #{locale} App Store metadata is available to copy" unless source
          desired = source.fetch("attributes").slice(*VERSION_METADATA_KEYS).merge(
            "locale" => locale,
            "whatsNew" => notes
          )
          validate_version_metadata!(locale, desired)
          if @apply
            log("CREATE #{locale} App Store version metadata from the current live listing with new release notes")
            @client.post(
              "/appStoreVersionLocalizations",
              {
                "data" => {
                  "type" => "appStoreVersionLocalizations",
                  "attributes" => desired,
                  "relationships" => {
                    "appStoreVersion" => {
                      "data" => { "type" => "appStoreVersions", "id" => version_id }
                    }
                  }
                }
              }
            )
          else
            log("PLAN copy current #{locale} App Store metadata and upload new release notes")
          end
          next
        end

        validate_version_metadata!(locale, localization.fetch("attributes"))
        next log("#{locale} release notes already match") if localization.dig("attributes", "whatsNew").to_s == notes
        unless @apply
          log("PLAN update #{locale} release notes")
          next
        end

        log("UPDATE #{locale} release notes")
        @client.patch(
          "/appStoreVersionLocalizations/#{localization.fetch('id')}",
          {
            "data" => {
              "type" => "appStoreVersionLocalizations",
              "id" => localization.fetch("id"),
              "attributes" => { "whatsNew" => notes }
            }
          }
        )
      end
    end

    def latest_sale_localizations(excluding_version_id)
      versions = @client.get(
        "/apps/#{@app_id}/appStoreVersions",
        "filter[platform]" => "IOS",
        "filter[appStoreState]" => "READY_FOR_SALE",
        "limit" => "50"
      ).fetch("data")
      source_version = versions.reject { |version| version.fetch("id") == excluding_version_id }.max_by do |version|
        Time.parse(version.dig("attributes", "createdDate") || "1970-01-01T00:00:00Z")
      end
      return {} unless source_version

      @client.get(
        "/appStoreVersions/#{source_version.fetch('id')}/appStoreVersionLocalizations",
        "limit" => "200"
      ).fetch("data").to_h do |localization|
        [localization.dig("attributes", "locale"), localization]
      end
    end

    def validate_version_metadata!(locale, attributes)
      required = %w[description keywords supportUrl]
      missing = required.select { |key| attributes[key].to_s.strip.empty? }
      raise Error, "#{locale} App Store metadata is missing: #{missing.join(', ')}" unless missing.empty?
    end

    def ensure_review_detail(version_id)
      detail = fetch_review_detail(version_id)
      if detail.nil?
        source = latest_sale_review_detail(version_id)
        raise Error, "no prior App Review detail is available to copy" unless source
        attributes = source.fetch("attributes").slice(*REVIEW_DETAIL_KEYS)
        validate_review_detail!(attributes)
        return log("PLAN copy existing App Review contact and demo-account details") unless @apply

        log("COPY existing App Review contact and demo-account details")
        @client.post(
          "/appStoreReviewDetails",
          {
            "data" => {
              "type" => "appStoreReviewDetails",
              "attributes" => attributes,
              "relationships" => {
                "appStoreVersion" => {
                  "data" => { "type" => "appStoreVersions", "id" => version_id }
                }
              }
            }
          }
        )
        detail = fetch_review_detail(version_id)
      end
      validate_review_detail!(detail.fetch("attributes"))
      log("App Review contact and demo-account details are present")
    end

    def validate_copy_sources(release_notes)
      source_localizations = latest_sale_localizations(nil)
      release_notes.each_key do |locale|
        source = source_localizations[locale]
        raise Error, "no prior #{locale} App Store metadata is available to copy" unless source

        validate_version_metadata!(locale, source.fetch("attributes"))
      end
      detail = latest_sale_review_detail(nil)
      raise Error, "no prior App Review detail is available to copy" unless detail

      validate_review_detail!(detail.fetch("attributes"))
      log("Validated current en-US/zh-Hans listing metadata and App Review details as copy sources")
    end

    def fetch_review_detail(version_id)
      response = @client.get("/appStoreVersions/#{version_id}/appStoreReviewDetail")
      response["data"]
    rescue ApiError => error
      raise unless error.status == 404

      nil
    end

    def latest_sale_review_detail(excluding_version_id)
      versions = @client.get(
        "/apps/#{@app_id}/appStoreVersions",
        "filter[platform]" => "IOS",
        "filter[appStoreState]" => "READY_FOR_SALE",
        "limit" => "50"
      ).fetch("data")
      versions.sort_by do |version|
        Time.parse(version.dig("attributes", "createdDate") || "1970-01-01T00:00:00Z")
      end.reverse_each do |version|
        next if version.fetch("id") == excluding_version_id

        detail = fetch_review_detail(version.fetch("id"))
        return detail if detail
      end
      nil
    end

    def validate_review_detail!(attributes)
      required = %w[contactEmail contactFirstName contactLastName contactPhone notes]
      required += %w[demoAccountName demoAccountPassword] if attributes["demoAccountRequired"]
      missing = required.select { |key| attributes[key].to_s.strip.empty? }
      raise Error, "App Review detail is missing required fields: #{missing.join(', ')}" unless missing.empty?
    end

    def ensure_submission(version_id)
      state = @client.get("/appStoreVersions/#{version_id}").dig("data", "attributes", "appStoreState")
      if SUBMITTED_VERSION_STATES.include?(state)
        submission = find_submission_for_version(version_id)
        raise Error, "version #{@version} is #{state}, but its review submission could not be resolved" unless submission
        log("Version #{@version} is already #{state}")
        return submission
      end

      active = active_review_submissions
      raise Error, "multiple active iOS review submissions exist" if active.length > 1
      submission = active.first
      if submission
        items = review_submission_items(submission.fetch("id"))
        item = items.find { |candidate| review_item_version_id(candidate) == version_id }
        if items.any? { |candidate| review_item_version_id(candidate).nil? }
          raise Error, "active review submission #{submission['id']} contains items whose App Store versions cannot be resolved"
        end
        unrelated = items.reject { |candidate| candidate == item }
        unless unrelated.empty?
          raise Error, "active review submission #{submission['id']} contains another App Store version"
        end
      elsif @apply
        log("CREATE review submission")
        submission = @client.post(
          "/reviewSubmissions",
          {
            "data" => {
              "type" => "reviewSubmissions",
              "attributes" => { "platform" => "IOS" },
              "relationships" => {
                "app" => { "data" => { "type" => "apps", "id" => @app_id } }
              }
            }
          }
        ).fetch("data")
      else
        log("PLAN create review submission, add version #{@version}, and submit")
        return nil
      end

      items ||= review_submission_items(submission.fetch("id"))
      item ||= items.find { |candidate| review_item_version_id(candidate) == version_id }
      rejected_item = item && %w[REJECTED UNRESOLVED_ISSUES].include?(item.dig("attributes", "state"))
      if rejected_item && @apply
        log("RESOLVE rejected review item #{item['id']} after updating version #{@version}")
        item = @client.patch(
          "/reviewSubmissionItems/#{item.fetch('id')}",
          {
            "data" => {
              "type" => "reviewSubmissionItems",
              "id" => item.fetch("id"),
              "attributes" => { "resolved" => true }
            }
          }
        ).fetch("data")
      end
      unless @apply
        log("PLAN mark rejected review item #{item['id']} resolved after updating version #{@version}") if rejected_item
        log(item ? "Version resource is already in review submission #{submission['id']}" : "PLAN add version #{@version} to review submission #{submission['id']}")
        log("PLAN submit review submission #{submission['id']}")
        return submission
      end

      if item.nil?
        log("ADD version #{@version} to review submission")
        item = @client.post(
          "/reviewSubmissionItems",
          {
            "data" => {
              "type" => "reviewSubmissionItems",
              "relationships" => {
                "reviewSubmission" => {
                  "data" => { "type" => "reviewSubmissions", "id" => submission.fetch("id") }
                },
                "appStoreVersion" => {
                  "data" => { "type" => "appStoreVersions", "id" => version_id }
                }
              }
            }
          }
        ).fetch("data")
      else
        log("Version resource is already in review submission #{submission['id']}")
      end

      submission = @client.get("/reviewSubmissions/#{submission.fetch('id')}").fetch("data")
      unless SUBMITTED_REVIEW_STATES.include?(submission.dig("attributes", "state"))
        log("SUBMIT review submission #{submission['id']}")
        submission = @client.patch(
          "/reviewSubmissions/#{submission.fetch('id')}",
          {
            "data" => {
              "type" => "reviewSubmissions",
              "id" => submission.fetch("id"),
              "attributes" => { "submitted" => true }
            }
          }
        ).fetch("data")
      end
      submission
    end

    def versions_for_string(version_string)
      @client.get(
        "/apps/#{@app_id}/appStoreVersions",
        "filter[platform]" => "IOS",
        "filter[versionString]" => version_string,
        "limit" => "50"
      ).fetch("data")
    end

    def active_review_submissions
      @client.get(
        "/apps/#{@app_id}/reviewSubmissions",
        "filter[platform]" => "IOS",
        "limit" => "200"
      ).fetch("data").reject do |submission|
        submission.dig("attributes", "state") == "COMPLETE"
      end
    end

    def review_submission_items(submission_id)
      @client.get(
        "/reviewSubmissions/#{submission_id}/items",
        "include" => "appStoreVersion",
        "limit" => "200"
      ).fetch("data")
    end

    def review_item_version_id(item)
      item.dig("relationships", "appStoreVersion", "data", "id")
    end

    def find_submission_for_version(version_id)
      submissions = @client.get(
        "/apps/#{@app_id}/reviewSubmissions",
        "filter[platform]" => "IOS",
        "include" => "appStoreVersionForReview",
        "limit" => "200"
      ).fetch("data")
      matches = submissions.select do |submission|
        submission.dig("relationships", "appStoreVersionForReview", "data", "id") == version_id
      end
      active_matches = matches.reject { |submission| submission.dig("attributes", "state") == "COMPLETE" }
      matches = active_matches unless active_matches.empty?
      if matches.length > 1
        raise Error, "multiple iOS review submissions are associated with App Store version #{@version}"
      end

      matches.first
    end

    def verify(version_id, build_id, release_notes, submission)
      version = @client.get("/appStoreVersions/#{version_id}", "include" => "build").fetch("data")
      attached = version.dig("relationships", "build", "data", "id")
      raise Error, "verification failed: App Store version has build #{attached || 'none'}, expected #{build_id}" unless attached == build_id
      raise Error, "verification failed: version string changed" unless version.dig("attributes", "versionString") == @version

      localizations = @client.get(
        "/appStoreVersions/#{version_id}/appStoreVersionLocalizations",
        "limit" => "200"
      ).fetch("data").to_h { |item| [item.dig("attributes", "locale"), item] }
      release_notes.each do |locale, notes|
        actual = localizations[locale]
        raise Error, "verification failed: #{locale} App Store metadata is missing" unless actual
        validate_version_metadata!(locale, actual.fetch("attributes"))
        unless actual.dig("attributes", "whatsNew").to_s == notes
          raise Error, "verification failed: #{locale} release notes differ"
        end
      end

      return unless @submit && @apply

      submission = @client.get(
        "/reviewSubmissions/#{submission.fetch('id')}",
        "include" => "appStoreVersionForReview"
      ).fetch("data")
      state = submission.dig("attributes", "state")
      unless SUBMITTED_REVIEW_STATES.include?(state)
        raise Error, "verification failed: review submission is #{state}"
      end
      associated_version_id = submission.dig("relationships", "appStoreVersionForReview", "data", "id")
      unless associated_version_id == version_id
        raise Error, "verification failed: review submission is associated with #{associated_version_id || 'no App Store version'}, expected #{@version}"
      end
      items = review_submission_items(submission.fetch("id"))
      item = items.find { |candidate| review_item_version_id(candidate) == version_id }
      raise Error, "verification failed: review submission does not contain version #{@version}" unless item
      if %w[REJECTED UNRESOLVED_ISSUES].include?(item.dig("attributes", "state"))
        raise Error, "verification failed: review item is #{item.dig('attributes', 'state')}"
      end
      log("SUBMITTED #{@version} (#{@build_number}) to App Review; submission #{submission['id']} is #{state}")
    end

    def log_metadata_plan(release_notes)
      release_notes.each_key do |locale|
        log("PLAN copy current #{locale} App Store metadata and upload #{@version} release notes")
      end
    end

    def log(message)
      @out.puts(message)
    end
  end

  def self.read_issuer_id(explicit, issuer_path)
    return explicit unless explicit.to_s.strip.empty?
    raise Error, "issuer ID is missing; pass --issuer-id or create #{issuer_path}" unless File.file?(issuer_path)

    File.read(issuer_path, encoding: "UTF-8").strip
  end

  def self.cli(argv)
    options = {
      app_id: ENV.fetch("ASC_APP_ID", DEFAULT_APP_ID),
      key_id: ENV.fetch("ASC_KEY_ID", DEFAULT_KEY_ID),
      issuer_id: ENV["ASC_ISSUER_ID"],
      issuer_path: File.expand_path("~/.appstoreconnect/private_keys/issuer"),
      release_notes: DEFAULT_RELEASE_NOTES,
      apply: false,
      submit: false,
      wait_seconds: 0
    }
    parser = OptionParser.new do |opts|
      opts.banner = "Usage: scripts/app_store_release.rb --version VERSION --binary-version VERSION --build-number NUMBER (--ci-build-run-id UUID | --uploaded-build-id UUID --artifact-path PATH --artifact-sha256 SHA256) --source-commit SHA [--apply --submit]"
      opts.on("--version VERSION", "Exact App Store listing version, for example 0.7.41") { |value| options[:version] = value }
      opts.on("--binary-version VERSION", "Exact marketing version embedded in the compiled binary") { |value| options[:binary_version] = value }
      opts.on("--build-number NUMBER", "Exact CFBundleVersion/App Store build number") { |value| options[:build_number] = value }
      opts.on("--ci-build-run-id UUID", "Exact Xcode Cloud build run ID") { |value| options[:ci_build_run_id] = value }
      opts.on("--uploaded-build-id UUID", "Exact App Store build resource ID for a locally uploaded artifact") { |value| options[:uploaded_build_id] = value }
      opts.on("--artifact-path PATH", "Local uploaded IPA path used to verify exact artifact identity") { |value| options[:artifact_path] = File.expand_path(value) }
      opts.on("--artifact-sha256 SHA256", "Expected SHA-256 of the locally uploaded IPA") { |value| options[:artifact_sha256] = value }
      opts.on("--source-commit SHA", "Source SHA (verified for Xcode Cloud; declared provenance for an uploaded IPA)") { |value| options[:source_commit] = value }
      opts.on("--release-notes-json PATH", "JSON object mapping en-US and zh-Hans to release notes") do |value|
        options[:release_notes] = JSON.parse(File.read(value, encoding: "UTF-8"))
      end
      opts.on("--app-id ID", "App Store Connect app resource ID") { |value| options[:app_id] = value }
      opts.on("--key-id ID", "App Store Connect API key ID") { |value| options[:key_id] = value }
      opts.on("--issuer-id ID", "App Store Connect API issuer ID") { |value| options[:issuer_id] = value }
      opts.on("--key-path PATH", "App Store Connect .p8 key path") { |value| options[:key_path] = value }
      opts.on("--issuer-path PATH", "File containing the issuer ID") { |value| options[:issuer_path] = value }
      opts.on("--wait-seconds SECONDS", Integer, "Wait for Xcode Cloud and App Store processing") { |value| options[:wait_seconds] = value }
      opts.on("--apply", "Create/update the version, build, and metadata") { options[:apply] = true }
      opts.on("--submit", "Include reviewSubmissions in the dry-run/apply workflow") { options[:submit] = true }
      opts.on("-h", "--help", "Show this help") do
        puts opts
        return 0
      end
    end
    parser.parse!(argv)
    %i[version binary_version build_number source_commit].each do |key|
      raise Error, "missing --#{key.to_s.tr('_', '-')}" if options[key].to_s.empty?
    end
    options[:issuer_id] = read_issuer_id(options[:issuer_id], options[:issuer_path])
    options[:key_path] ||= File.expand_path("~/.appstoreconnect/private_keys/AuthKey_#{options[:key_id]}.p8")
    raise Error, "App Store Connect key does not exist: #{options[:key_path]}" unless File.file?(options[:key_path])

    client = Client.new(
      key_id: options[:key_id],
      issuer_id: options[:issuer_id],
      key_path: options[:key_path]
    )
    Runner.new(
      client: client,
      app_id: options[:app_id],
      version: options[:version],
      binary_version: options[:binary_version],
      build_number: options[:build_number],
      ci_build_run_id: options[:ci_build_run_id],
      uploaded_build_id: options[:uploaded_build_id],
      artifact_path: options[:artifact_path],
      artifact_sha256: options[:artifact_sha256],
      source_commit: options[:source_commit],
      release_notes: options[:release_notes],
      apply: options[:apply],
      submit: options[:submit],
      wait_seconds: options[:wait_seconds]
    ).run
    0
  rescue OptionParser::ParseError, JSON::ParserError, Error, Errno::ENOENT, OpenSSL::PKey::PKeyError => error
    warn("error: #{error.message}")
    1
  end
end

exit(MithkaAppStoreRelease.cli(ARGV)) if $PROGRAM_NAME == __FILE__
