# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../../scripts/app_store_workflow"

class AppStoreWorkflowTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir("store-workflow-test")
    FileUtils.mkdir_p(File.join(@root, "distribution/app-store"))
    @notes = "distribution/app-store/notes.json"
    File.write(File.join(@root, @notes), '{"en-US":"Changes","zh-Hans":"Changes"}')
    @env = {
      "GITHUB_REPOSITORY" => "iebb/mithka", "GITHUB_REF" => "refs/heads/master",
      "GITHUB_EVENT_NAME" => "workflow_dispatch", "STORE_OPERATION" => "validate",
      "STORE_PLATFORM" => "IOS", "STORE_VERSION" => "1.8.0",
      "STORE_BUILD_NUMBER" => "1234", "STORE_SOURCE_COMMIT" => "a" * 40,
      "STORE_PROVENANCE" => "github_actions", "STORE_BUILD_RUN_ID" => "123456",
      "STORE_UPLOADED_BUILD_ID" => "12345678-1234-1234-1234-123456789abc",
      "STORE_RELEASE_NOTES_PATH" => @notes, "ASC_KEY_ID" => "test-key",
      "ASC_ISSUER_ID" => "test-issuer", "ASC_KEY_PATH" => "/unused/test-key.p8"
    }
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def arguments
    MithkaAppStoreWorkflow.arguments(@env, root: @root)
  end

  def test_validation_plans_review_without_enabling_writes
    args = arguments
    assert_includes args, "--submit"
    refute_includes args, "--apply"
    assert_equal "1.8.0", args[args.index("--binary-version") + 1]
    assert_equal "123456", args[args.index("--github-run-id") + 1]
  end

  def test_only_explicit_submit_enables_writes
    @env["STORE_OPERATION"] = "submit"
    assert_equal 1, arguments.count("--apply")
    @env["STORE_OPERATION"] = "true"
    assert_raises(MithkaAppStoreWorkflow::Error) { arguments }
  end

  def test_only_canonical_master_manual_dispatch_is_allowed
    {
      "GITHUB_REPOSITORY" => "someone/mithka",
      "GITHUB_REF" => "refs/heads/release",
      "GITHUB_EVENT_NAME" => "pull_request_target"
    }.each do |key, value|
      original = @env[key]
      @env[key] = value
      assert_raises(MithkaAppStoreWorkflow::Error) { arguments }
      @env[key] = original
    end
  end

  def test_github_upload_requires_exact_asc_build
    @env.delete("STORE_UPLOADED_BUILD_ID")
    assert_raises(MithkaAppStoreWorkflow::Error) { arguments }
  end

  def test_cloud_provenance_uses_only_the_cloud_run
    @env["STORE_PROVENANCE"] = "xcode_cloud"
    @env["STORE_BUILD_RUN_ID"] = "abcdef01-1234-1234-1234-123456789abc"
    assert_raises(MithkaAppStoreWorkflow::Error) { arguments }
    @env.delete("STORE_UPLOADED_BUILD_ID")
    @env["STORE_PLATFORM"] = "MAC_OS"
    args = arguments
    assert_includes args, "--ci-build-run-id"
    refute_includes args, "--github-run-id"
    refute_includes args, "--uploaded-build-id"
  end

  def test_unknown_provenance_is_rejected
    @env["STORE_PROVENANCE"] = "latest_build"
    assert_raises(MithkaAppStoreWorkflow::Error) { arguments }
  end

  def test_absolute_traversal_and_other_directory_notes_are_rejected
    File.write(File.join(@root, "outside.json"), "{}")
    [File.join(@root, @notes), "distribution/app-store/../../outside.json", "outside.json"].each do |path|
      @env["STORE_RELEASE_NOTES_PATH"] = path
      assert_raises(MithkaAppStoreWorkflow::Error) { arguments }
    end
  end

  def test_symlink_cannot_escape_the_metadata_directory
    File.write(File.join(@root, "outside.json"), "{}")
    File.symlink(File.join(@root, "outside.json"), File.join(@root, "distribution/app-store/link.json"))
    @env["STORE_RELEASE_NOTES_PATH"] = "distribution/app-store/link.json"
    assert_raises(MithkaAppStoreWorkflow::Error) { arguments }
  end

  def test_binary_version_can_differ_from_listing_version
    @env["STORE_BINARY_VERSION"] = "1.8.1"
    args = arguments
    assert_equal "1.8.1", args[args.index("--binary-version") + 1]
  end

  def test_inputs_are_arguments_and_cannot_execute_shell_commands
    marker = File.join(@root, "should-not-exist")
    @env["STORE_BUILD_NUMBER"] = "$(touch #{marker})"
    assert_includes arguments, "$(touch #{marker})"
    refute File.exist?(marker)
  end

  def test_listing_preserves_the_normal_source_patch
    reader = ->(_sha) { "1.8.8" }
    MithkaAppStoreWorkflow.verify_source_version!("1.8.8", "a" * 40, reader: reader)
    error = assert_raises(MithkaAppStoreWorkflow::Error) do
      MithkaAppStoreWorkflow.verify_source_version!("1.8.0", "a" * 40, reader: reader)
    end
    assert_includes error.message, "expected 1.8.8"
  end

  def test_source_version_is_read_from_the_exact_github_commit
    response = JSON.generate({
      "encoding" => "base64", "content" => Base64.strict_encode64("name: mithka\nversion: 1.8.8+296\n")
    })
    success = Struct.new(:success?).new(true)
    calls = []
    stub = lambda do |*args|
      calls << args
      [response, "", success]
    end
    assert_equal "1.8.8", MithkaAppStoreWorkflow.source_version("b" * 40, command_runner: stub)
    assert_equal ["gh", "api", "repos/iebb/mithka/contents/pubspec.yaml?ref=#{'b' * 40}"], calls.first
    assert_raises(MithkaAppStoreWorkflow::Error) { MithkaAppStoreWorkflow.source_version("latest") }
  end
end
