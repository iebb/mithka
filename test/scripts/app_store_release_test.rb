# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "stringio"
require "tmpdir"

require_relative "../../scripts/app_store_release"

class AppStoreReleaseTest < Minitest::Test
  RUN_ID = "1d4fc66c-e159-4054-9510-53cec367ed30"
  SOURCE_SHA = "054ff93ff892b4779596f3c602a8d8795d447e3c"
  BUILD_ID = "2f98db03-3385-4fba-b0e2-f685f6ae1bda"
  APP_ID = "6783830742"
  SOURCE_VERSION_ID = "e7ed3f48-e93d-4f33-ba99-0feb84454462"
  TARGET_VERSION_ID = "3a297302-6ebd-499b-86aa-e57ae6da4766"
  SUBMISSION_ID = "51460acf-3238-49cc-bf75-1f4687bb73cd"
  UPLOADED_BUILD_ID = "28ad1b06-7884-4482-ae22-5c1b315e97c9"
  GITHUB_RUN_ID = "31586409622"

  class FakeGitHubVerifier
    attr_reader :calls

    def initialize
      @calls = []
    end

    def verify!(**arguments)
      @calls << arguments
    end
  end

  class FakeClient
    attr_reader :writes

    def initialize(routes)
      @routes = routes
      @writes = []
    end

    def get(path, params = {})
      value = @routes.fetch([path, params]) { @routes.fetch(path) }
      Marshal.load(Marshal.dump(value))
    end

    def post(path, body)
      @writes << [:post, path, body]
      raise "unexpected POST #{path}"
    end

    def patch(path, body)
      @writes << [:patch, path, body]
      raise "unexpected PATCH #{path}"
    end
  end

  class SubmissionClient
    attr_reader :writes

    def initialize(version_state: "PREPARE_FOR_SUBMISSION", has_item: false,
                   item_state: "READY_FOR_REVIEW", submission_state: "READY_FOR_REVIEW")
      @version_string = "0.7.41"
      @version_state = version_state
      @has_item = has_item
      @item_state = item_state
      @submission_state = submission_state
      @writes = []
    end

    def get(path, params = {})
      case [path, params]
      when ["/appStoreVersions/#{TARGET_VERSION_ID}", {}]
        { "data" => { "id" => TARGET_VERSION_ID, "attributes" => { "appStoreState" => @version_state, "versionString" => @version_string } } }
      when ["/apps/#{APP_ID}/reviewSubmissions", { "filter[platform]" => "IOS", "limit" => "200" }]
        { "data" => [{ "id" => SUBMISSION_ID, "attributes" => { "state" => @submission_state } }] }
      when ["/apps/#{APP_ID}/reviewSubmissions", { "filter[platform]" => "IOS", "include" => "appStoreVersionForReview", "limit" => "200" }]
        {
          "data" => [{
            "id" => SUBMISSION_ID,
            "attributes" => { "state" => @submission_state },
            "relationships" => {
              "appStoreVersionForReview" => {
                "data" => { "type" => "appStoreVersions", "id" => TARGET_VERSION_ID }
              }
            }
          }]
        }
      when ["/reviewSubmissions/#{SUBMISSION_ID}/items", { "include" => "appStoreVersion", "limit" => "200" }]
        items = if @has_item
                  [{
                    "id" => "item",
                    "attributes" => { "state" => @item_state },
                    "relationships" => {
                      "appStoreVersion" => {
                        "data" => { "type" => "appStoreVersions", "id" => TARGET_VERSION_ID }
                      }
                    }
                  }]
                else
                  []
                end
        { "data" => items }
      when ["/apps/#{APP_ID}/appStoreVersions", { "filter[platform]" => "IOS", "filter[versionString]" => "0.7.0", "limit" => "50" }]
        { "data" => [] }
      when ["/reviewSubmissions/#{SUBMISSION_ID}", {}]
        { "data" => { "id" => SUBMISSION_ID, "attributes" => { "state" => @submission_state } } }
      else
        raise "unexpected GET #{path} #{params}"
      end
    end

    def post(path, body)
      @writes << [:post, path, body]
      raise "unexpected POST #{path}" unless path == "/reviewSubmissionItems"

      { "data" => { "id" => "item", "attributes" => { "state" => "READY_FOR_REVIEW" } } }
    end

    def patch(path, body)
      @writes << [:patch, path, body]
      if path == "/appStoreVersions/#{TARGET_VERSION_ID}"
        @version_string = body.dig("data", "attributes", "versionString")
        return { "data" => { "id" => TARGET_VERSION_ID, "attributes" => { "versionString" => @version_string } } }
      end
      if path == "/reviewSubmissions/#{SUBMISSION_ID}"
        @submission_state = "WAITING_FOR_REVIEW"
        return { "data" => { "id" => SUBMISSION_ID, "attributes" => { "state" => @submission_state } } }
      end
      if path == "/reviewSubmissionItems/item"
        @item_state = "READY_FOR_REVIEW"
        return { "data" => { "id" => "item", "attributes" => { "state" => @item_state } } }
      end

      raise "unexpected PATCH #{path}"
    end
  end

  def test_dry_run_resolves_binary_version_separately_from_listing_version
    client = FakeClient.new(base_routes)
    output = StringIO.new

    runner = build_runner(client, output)
    runner.run

    assert_equal BUILD_ID, runner.resolved_build_id
    assert_empty client.writes
    assert_includes output.string, "binary 0.7.0 (345)"
    assert_includes output.string, "listing version 0.7.41"
    assert_includes output.string, "PLAN submit through reviewSubmissions"
    assert_includes output.string, "no App Store Connect state was changed"
  end

  def test_exact_uploaded_artifact_resolves_by_build_id_and_sha256
    with_artifact do |path, sha256|
      client = FakeClient.new(uploaded_build_routes)
      output = StringIO.new
      runner = build_uploaded_runner(client, output, path, sha256)

      build = runner.send(:resolve_exact_build)

      assert_equal UPLOADED_BUILD_ID, build.fetch("id")
      assert_includes output.string, "SHA-256 #{sha256}"
      assert_includes output.string, "binary 0.7.41 (346)"
      assert_includes output.string, "declared source provenance #{SOURCE_SHA}"
      assert_empty client.writes
    end
  end

  def test_exact_github_actions_upload_resolves_by_run_and_build_id
    client = FakeClient.new(uploaded_build_routes)
    verifier = FakeGitHubVerifier.new
    output = StringIO.new
    runner = build_github_runner(client, output, verifier)

    build = runner.send(:resolve_exact_build)

    assert_equal UPLOADED_BUILD_ID, build.fetch("id")
    assert_equal [{ run_id: GITHUB_RUN_ID, source_commit: SOURCE_SHA, build_number: "346" }], verifier.calls
    assert_includes output.string, "GitHub Actions run #{GITHUB_RUN_ID}"
    assert_includes output.string, "binary 0.7.41 (346)"
    assert_includes output.string, "source #{SOURCE_SHA}"
    assert_empty client.writes
  end

  def test_uploaded_artifact_sha256_must_match_before_build_is_used
    with_artifact do |path, _sha256|
      client = FakeClient.new(uploaded_build_routes)
      runner = build_uploaded_runner(client, StringIO.new, path, "a" * 64)

      error = assert_raises(MithkaAppStoreRelease::Error) { runner.send(:resolve_exact_build) }

      assert_includes error.message, "artifact SHA-256"
      assert_empty client.writes
    end
  end

  def test_uploaded_artifact_info_plist_must_match_remote_identity
    with_artifact(short_version: "0.7.40") do |path, sha256|
      client = FakeClient.new(uploaded_build_routes)
      runner = build_uploaded_runner(client, StringIO.new, path, sha256)

      error = assert_raises(MithkaAppStoreRelease::Error) { runner.send(:resolve_exact_build) }

      assert_includes error.message, "CFBundleShortVersionString"
      assert_includes error.message, "0.7.40"
      assert_empty client.writes
    end
  end

  def test_uploaded_artifact_bundle_and_build_must_match_remote_identity
    [
      [{ bundle_id: "example.invalid" }, "CFBundleIdentifier"],
      [{ build_number: "347" }, "CFBundleVersion"]
    ].each do |artifact_options, expected_key|
      with_artifact(**artifact_options) do |path, sha256|
        client = FakeClient.new(uploaded_build_routes)
        runner = build_uploaded_runner(client, StringIO.new, path, sha256)

        error = assert_raises(MithkaAppStoreRelease::Error) { runner.send(:resolve_exact_build) }

        assert_includes error.message, expected_key
        assert_empty client.writes
      end
    end
  end

  def test_uploaded_mode_full_dry_run_is_read_only
    with_artifact do |path, sha256|
      client = FakeClient.new(base_routes.merge(uploaded_build_routes))
      output = StringIO.new

      build_uploaded_runner(client, output, path, sha256).run

      assert_empty client.writes
      assert_includes output.string, "Validated current en-US/zh-Hans listing metadata"
      assert_includes output.string, "PLAN create iOS App Store version 0.7.41"
      assert_includes output.string, "DRY RUN complete"
    end
  end

  def test_uploaded_mode_rejects_partial_or_mixed_provenance_options
    with_artifact do |path, sha256|
      common = {
        client: FakeClient.new({}), app_id: APP_ID, version: "0.7.41",
        binary_version: "0.7.41", build_number: "346", source_commit: SOURCE_SHA,
        release_notes: MithkaAppStoreRelease::DEFAULT_RELEASE_NOTES,
        apply: false, submit: true, out: StringIO.new
      }

      partial = assert_raises(MithkaAppStoreRelease::Error) do
        MithkaAppStoreRelease::Runner.new(**common, uploaded_build_id: UPLOADED_BUILD_ID)
      end
      mixed = assert_raises(MithkaAppStoreRelease::Error) do
        MithkaAppStoreRelease::Runner.new(
          **common,
          ci_build_run_id: RUN_ID,
          uploaded_build_id: UPLOADED_BUILD_ID,
          artifact_path: path,
          artifact_sha256: sha256
        )
      end

      assert_includes partial.message, "must be supplied together"
      assert_includes mixed.message, "either --ci-build-run-id or --uploaded-build-id"
    end
  end

  def test_source_commit_must_match_exactly
    routes = base_routes
    routes["/ciBuildRuns/#{RUN_ID}"]["data"]["attributes"]["sourceCommit"]["commitSha"] = "a" * 40
    client = FakeClient.new(routes)

    error = assert_raises(MithkaAppStoreRelease::Error) do
      build_runner(client, StringIO.new).run
    end
    assert_includes error.message, "expected #{SOURCE_SHA}"
    assert_empty client.writes
  end

  def test_binary_marketing_version_must_match
    routes = base_routes
    routes["/builds/#{BUILD_ID}/preReleaseVersion"]["data"]["attributes"]["version"] = "0.7.1"
    client = FakeClient.new(routes)

    error = assert_raises(MithkaAppStoreRelease::Error) do
      build_runner(client, StringIO.new).run
    end
    assert_includes error.message, "binary marketing version 0.7.1, expected 0.7.0"
    assert_empty client.writes
  end

  def test_mismatched_binary_is_submitted_without_renaming_listing
    client = SubmissionClient.new
    runner = build_runner(client, StringIO.new, apply: true)

    submission = runner.send(:ensure_submission, TARGET_VERSION_ID)

    assert_equal "WAITING_FOR_REVIEW", submission.dig("attributes", "state")
    mutations = client.writes.map do |method, path, body|
      if path == "/appStoreVersions/#{TARGET_VERSION_ID}"
        [method, path, body.dig("data", "attributes", "versionString")]
      else
        [method, path]
      end
    end
    assert_equal [
      [:post, "/reviewSubmissionItems"],
      [:patch, "/reviewSubmissions/#{SUBMISSION_ID}"]
    ], mutations
  end

  def test_dry_run_with_active_submission_never_writes
    client = SubmissionClient.new
    output = StringIO.new
    runner = build_runner(client, output, apply: false)

    submission = runner.send(:ensure_submission, TARGET_VERSION_ID)

    assert_equal "READY_FOR_REVIEW", submission.dig("attributes", "state")
    assert_empty client.writes
    assert_includes output.string, "PLAN add version 0.7.41"
    assert_includes output.string, "PLAN submit review submission"
  end

  def test_ready_for_review_version_is_resumable
    client = SubmissionClient.new(version_state: "READY_FOR_REVIEW", has_item: true)
    runner = build_runner(client, StringIO.new, apply: true)

    version =
      { "id" => TARGET_VERSION_ID, "attributes" => { "appStoreState" => "READY_FOR_REVIEW" } }
    runner.send(
      :ensure_version_can_be_used!,
      version
    )
    submission = runner.send(:ensure_submission, TARGET_VERSION_ID)

    assert_equal "WAITING_FOR_REVIEW", submission.dig("attributes", "state")
    assert_equal [[:patch, "/reviewSubmissions/#{SUBMISSION_ID}"]], client.writes.map { |method, path, _body| [method, path] }
  end

  def test_waiting_for_review_version_uses_authoritative_submission_relationship
    client = SubmissionClient.new(version_state: "WAITING_FOR_REVIEW", has_item: true)
    runner = build_runner(client, StringIO.new, apply: true)

    submission = runner.send(:ensure_submission, TARGET_VERSION_ID)

    assert_equal SUBMISSION_ID, submission.fetch("id")
    assert_equal "READY_FOR_REVIEW", submission.dig("attributes", "state")
    assert_empty client.writes
  end

  def test_rejected_item_is_resolved_before_resubmission
    client = SubmissionClient.new(
      version_state: "INVALID_BINARY",
      has_item: true,
      item_state: "REJECTED",
      submission_state: "UNRESOLVED_ISSUES"
    )
    output = StringIO.new
    runner = build_runner(client, output, apply: true)

    submission = runner.send(:ensure_submission, TARGET_VERSION_ID)

    assert_equal "WAITING_FOR_REVIEW", submission.dig("attributes", "state")
    assert_equal [
      [:patch, "/reviewSubmissionItems/item"],
      [:patch, "/reviewSubmissions/#{SUBMISSION_ID}"]
    ], client.writes.map { |method, path, _body| [method, path] }
    resolved_body = client.writes.first.last
    assert_equal true, resolved_body.dig("data", "attributes", "resolved")
    assert_includes output.string, "RESOLVE rejected review item"
  end

  def test_rejected_item_dry_run_plans_resolution_without_writes
    client = SubmissionClient.new(
      version_state: "INVALID_BINARY",
      has_item: true,
      item_state: "REJECTED",
      submission_state: "UNRESOLVED_ISSUES"
    )
    output = StringIO.new
    runner = build_runner(client, output)

    runner.send(:ensure_submission, TARGET_VERSION_ID)

    assert_empty client.writes
    assert_includes output.string, "PLAN mark rejected review item item resolved"
    assert_includes output.string, "PLAN submit review submission"
  end

  def test_dry_run_with_existing_partial_version_plans_without_strict_verification
    routes = base_routes.merge(
      ["/apps/#{APP_ID}/appStoreVersions", {
        "filter[platform]" => "IOS",
        "filter[versionString]" => "0.7.41",
        "limit" => "50"
      }] => {
        "data" => [{ "id" => TARGET_VERSION_ID, "attributes" => { "appStoreState" => "PREPARE_FOR_SUBMISSION", "versionString" => "0.7.41" } }]
      },
      ["/appStoreVersions/#{TARGET_VERSION_ID}", { "include" => "build" }] => {
        "data" => {
          "id" => TARGET_VERSION_ID,
          "attributes" => { "appStoreState" => "PREPARE_FOR_SUBMISSION", "versionString" => "0.7.41" },
          "relationships" => { "build" => { "data" => nil } }
        }
      },
      ["/appStoreVersions/#{TARGET_VERSION_ID}/appStoreVersionLocalizations", { "limit" => "200" }] => {
        "data" => %w[en-US zh-Hans].map do |locale|
          {
            "id" => "target-localization-#{locale}",
            "attributes" => {
              "locale" => locale,
              "description" => "Description",
              "keywords" => "chat,messaging",
              "supportUrl" => "https://example.com/support",
              "whatsNew" => "Old notes"
            }
          }
        end
      },
      "/appStoreVersions/#{TARGET_VERSION_ID}/appStoreReviewDetail" => {
        "data" => base_routes.fetch("/appStoreVersions/#{SOURCE_VERSION_ID}/appStoreReviewDetail").fetch("data")
      },
      "/appStoreVersions/#{TARGET_VERSION_ID}" => {
        "data" => { "id" => TARGET_VERSION_ID, "attributes" => { "appStoreState" => "PREPARE_FOR_SUBMISSION", "versionString" => "0.7.41" } }
      },
      ["/apps/#{APP_ID}/reviewSubmissions", { "filter[platform]" => "IOS", "limit" => "200" }] => {
        "data" => [{ "id" => SUBMISSION_ID, "attributes" => { "state" => "READY_FOR_REVIEW" } }]
      },
      ["/reviewSubmissions/#{SUBMISSION_ID}/items", { "include" => "appStoreVersion", "limit" => "200" }] => { "data" => [] }
    )
    client = FakeClient.new(routes)
    output = StringIO.new

    build_runner(client, output).run

    assert_empty client.writes
    assert_includes output.string, "PLAN attach build 345"
    assert_includes output.string, "PLAN update en-US release notes"
    assert_includes output.string, "DRY RUN complete"
  end

  def test_apply_verifies_final_submitted_state_through_authoritative_relationships
    client = FakeClient.new(base_routes.merge(submitted_routes))
    output = StringIO.new

    build_runner(client, output, apply: true).run

    assert_empty client.writes
    assert_includes output.string, "Version 0.7.41 is already WAITING_FOR_REVIEW"
    assert_includes output.string, "SUBMITTED 0.7.41 (345) to App Review"
    assert_includes output.string, "App Store release preparation verified"
  end

  private

  def build_runner(client, output, apply: false)
    MithkaAppStoreRelease::Runner.new(
      client: client,
      app_id: APP_ID,
      version: "0.7.41",
      binary_version: "0.7.0",
      build_number: "345",
      ci_build_run_id: RUN_ID,
      source_commit: SOURCE_SHA,
      release_notes: MithkaAppStoreRelease::DEFAULT_RELEASE_NOTES,
      apply: apply,
      submit: true,
      out: output
    )
  end

  def build_uploaded_runner(client, output, artifact_path, artifact_sha256)
    MithkaAppStoreRelease::Runner.new(
      client: client,
      app_id: APP_ID,
      version: "0.7.41",
      binary_version: "0.7.41",
      build_number: "346",
      uploaded_build_id: UPLOADED_BUILD_ID,
      artifact_path: artifact_path,
      artifact_sha256: artifact_sha256,
      source_commit: SOURCE_SHA,
      release_notes: MithkaAppStoreRelease::DEFAULT_RELEASE_NOTES,
      apply: false,
      submit: true,
      out: output
    )
  end

  def build_github_runner(client, output, verifier)
    MithkaAppStoreRelease::Runner.new(
      client: client,
      app_id: APP_ID,
      version: "0.7.41",
      binary_version: "0.7.41",
      build_number: "346",
      github_run_id: GITHUB_RUN_ID,
      github_verifier: verifier,
      uploaded_build_id: UPLOADED_BUILD_ID,
      source_commit: SOURCE_SHA,
      release_notes: MithkaAppStoreRelease::DEFAULT_RELEASE_NOTES,
      apply: false,
      submit: true,
      out: output
    )
  end

  def with_artifact(bundle_id: "ad.neko.mithka", short_version: "0.7.41", build_number: "346")
    Dir.mktmpdir("mithka-release") do |directory|
      app_directory = File.join(directory, "Payload", "Runner.app")
      FileUtils.mkdir_p(app_directory)
      File.write(
        File.join(app_directory, "Info.plist"),
        <<~PLIST
          <?xml version="1.0" encoding="UTF-8"?>
          <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
          <plist version="1.0"><dict>
            <key>CFBundleIdentifier</key><string>#{bundle_id}</string>
            <key>CFBundleShortVersionString</key><string>#{short_version}</string>
            <key>CFBundleVersion</key><string>#{build_number}</string>
          </dict></plist>
        PLIST
      )
      artifact_path = File.join(directory, "Mithka.ipa")
      _stdout, stderr, status = Open3.capture3("zip", "-q", "-r", artifact_path, "Payload", chdir: directory)
      raise "failed to create IPA fixture: #{stderr}" unless status.success?

      yield artifact_path, Digest::SHA256.file(artifact_path).hexdigest
    end
  end

  def uploaded_build_routes
    {
      "/builds/#{UPLOADED_BUILD_ID}" => {
        "data" => {
          "id" => UPLOADED_BUILD_ID,
          "attributes" => {
            "version" => "346",
            "processingState" => "VALID",
            "expired" => false,
            "buildAudienceType" => "APP_STORE_ELIGIBLE"
          }
        }
      },
      "/builds/#{UPLOADED_BUILD_ID}/app" => {
        "data" => { "type" => "apps", "id" => APP_ID, "attributes" => { "bundleId" => "ad.neko.mithka" } }
      },
      "/builds/#{UPLOADED_BUILD_ID}/preReleaseVersion" => {
        "data" => {
          "type" => "preReleaseVersions",
          "id" => "uploaded-prerelease",
          "attributes" => { "version" => "0.7.41" }
        }
      }
    }
  end

  def submitted_routes
    target_localizations = MithkaAppStoreRelease::DEFAULT_RELEASE_NOTES.map do |locale, notes|
      {
        "id" => "target-localization-#{locale}",
        "attributes" => {
          "locale" => locale,
          "description" => "Description",
          "keywords" => "chat,messaging",
          "supportUrl" => "https://example.com/support",
          "whatsNew" => notes
        }
      }
    end
    target_review_detail = base_routes.fetch("/appStoreVersions/#{SOURCE_VERSION_ID}/appStoreReviewDetail")
    submission = {
      "id" => SUBMISSION_ID,
      "attributes" => { "state" => "WAITING_FOR_REVIEW" },
      "relationships" => {
        "appStoreVersionForReview" => {
          "data" => { "type" => "appStoreVersions", "id" => TARGET_VERSION_ID }
        }
      }
    }
    {
      ["/apps/#{APP_ID}/appStoreVersions", {
        "filter[platform]" => "IOS",
        "filter[versionString]" => "0.7.41",
        "limit" => "50"
      }] => {
        "data" => [{
          "id" => TARGET_VERSION_ID,
          "attributes" => { "appStoreState" => "WAITING_FOR_REVIEW", "versionString" => "0.7.41" }
        }]
      },
      ["/appStoreVersions/#{TARGET_VERSION_ID}", { "include" => "build" }] => {
        "data" => {
          "id" => TARGET_VERSION_ID,
          "attributes" => { "appStoreState" => "WAITING_FOR_REVIEW", "versionString" => "0.7.41" },
          "relationships" => { "build" => { "data" => { "type" => "builds", "id" => BUILD_ID } } }
        }
      },
      ["/appStoreVersions/#{TARGET_VERSION_ID}/appStoreVersionLocalizations", { "limit" => "200" }] => {
        "data" => target_localizations
      },
      "/appStoreVersions/#{TARGET_VERSION_ID}/appStoreReviewDetail" => target_review_detail,
      "/appStoreVersions/#{TARGET_VERSION_ID}" => {
        "data" => {
          "id" => TARGET_VERSION_ID,
          "attributes" => { "appStoreState" => "WAITING_FOR_REVIEW", "versionString" => "0.7.41" }
        }
      },
      ["/apps/#{APP_ID}/reviewSubmissions", {
        "filter[platform]" => "IOS",
        "include" => "appStoreVersionForReview",
        "limit" => "200"
      }] => { "data" => [submission] },
      ["/reviewSubmissions/#{SUBMISSION_ID}", { "include" => "appStoreVersionForReview" }] => {
        "data" => submission
      },
      ["/reviewSubmissions/#{SUBMISSION_ID}/items", {
        "include" => "appStoreVersion",
        "limit" => "200"
      }] => {
        "data" => [{
          "id" => "submitted-item",
          "attributes" => { "state" => "WAITING_FOR_REVIEW" },
          "relationships" => {
            "appStoreVersion" => {
              "data" => { "type" => "appStoreVersions", "id" => TARGET_VERSION_ID }
            }
          }
        }]
      }
    }
  end

  def base_routes
    {
      "/ciBuildRuns/#{RUN_ID}" => {
        "data" => {
          "id" => RUN_ID,
          "attributes" => {
            "executionProgress" => "COMPLETE",
            "completionStatus" => "SUCCEEDED",
            "sourceCommit" => { "commitSha" => SOURCE_SHA }
          }
        }
      },
      ["/ciBuildRuns/#{RUN_ID}/builds", { "limit" => "200" }] => {
        "data" => [
          {
            "id" => BUILD_ID,
            "attributes" => {
              "version" => "345",
              "processingState" => "VALID",
              "expired" => false,
              "buildAudienceType" => "APP_STORE_ELIGIBLE"
            }
          }
        ]
      },
      "/builds/#{BUILD_ID}/app" => {
        "data" => { "type" => "apps", "id" => APP_ID }
      },
      "/builds/#{BUILD_ID}/preReleaseVersion" => {
        "data" => {
          "type" => "preReleaseVersions",
          "id" => "prerelease",
          "attributes" => { "version" => "0.7.0" }
        }
      },
      ["/apps/#{APP_ID}/appStoreVersions", {
        "filter[platform]" => "IOS",
        "filter[versionString]" => "0.7.41",
        "limit" => "50"
      }] => { "data" => [] },
      ["/apps/#{APP_ID}/appStoreVersions", {
        "filter[platform]" => "IOS",
        "filter[appStoreState]" => "READY_FOR_SALE",
        "limit" => "50"
      }] => {
        "data" => [{ "id" => SOURCE_VERSION_ID, "attributes" => { "appStoreState" => "READY_FOR_SALE", "createdDate" => "2026-07-14T00:00:00Z" } }]
      },
      ["/appStoreVersions/#{SOURCE_VERSION_ID}/appStoreVersionLocalizations", { "limit" => "200" }] => {
        "data" => %w[en-US zh-Hans].map do |locale|
          {
            "id" => "localization-#{locale}",
            "attributes" => {
              "locale" => locale,
              "description" => "Description",
              "keywords" => "chat,messaging",
              "supportUrl" => "https://example.com/support"
            }
          }
        end
      },
      "/appStoreVersions/#{SOURCE_VERSION_ID}/appStoreReviewDetail" => {
        "data" => {
          "id" => "review-detail",
          "attributes" => {
            "contactEmail" => "review@example.com",
            "contactFirstName" => "App",
            "contactLastName" => "Review",
            "contactPhone" => "+10000000000",
            "demoAccountRequired" => true,
            "demoAccountName" => "reviewer",
            "demoAccountPassword" => "secret",
            "notes" => "Sign in with the review account."
          }
        }
      }
    }
  end

end
