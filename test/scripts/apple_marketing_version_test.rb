# frozen_string_literal: true

require "minitest/autorun"
require "open3"

# Apple uploads retain the exact source/GitHub marketing version, including its
# patch, on every branch. The +build suffix is independent of that version.
class AppleMarketingVersionTest < Minitest::Test
  SCRIPT = File.expand_path("../../scripts/apple_marketing_version.sh", __dir__)
  REPOSITORY = File.expand_path("../..", __dir__)

  def test_nightly_keeps_each_computed_patch
    assert_equal "1.2.1", marketing_version("1.2.1+285", "nightly")
    assert_equal "1.2.7", marketing_version("1.2.7+291", "nightly")
    assert_equal "1.2.0", marketing_version("1.2.0+285", "nightly")
    assert_equal "1.8.4", marketing_version("1.8.4", "nightly")
    assert_equal "1.8.4", marketing_version("1.8.4", "nightly-ios")
  end

  def test_a_release_keeps_the_patch_it_ships
    assert_equal "1.1.2", marketing_version("1.1.2+284", "release")
    assert_equal "1.2.0", marketing_version("1.2.0+285", "release")
    assert_equal "1.1.2", marketing_version("1.1.2+284", "release-ios")
    assert_equal "1.1.2", marketing_version("1.1.2+284", "release-macos/1.1")
    assert_equal "1.1.2", marketing_version("1.1.2+284", "release/1.1")
  end

  def test_master_and_other_refs_keep_the_patch
    ["master", "codex/some-branch", "prerelease", "releases"].each do |branch|
      assert_equal "1.1.2", marketing_version("1.1.2+284", branch),
                   "expected #{branch.inspect} to preserve the source patch"
    end
  end

  def test_a_missing_or_empty_branch_keeps_the_patch
    assert_equal "1.1.2", marketing_version("1.1.2+284")
    assert_equal "1.1.2", marketing_version("1.1.2+284", "")
  end

  def test_major_minor_and_patch_are_preserved
    assert_equal "1.3.1", marketing_version("1.3.1+300", "nightly")
    assert_equal "2.0.4", marketing_version("2.0.4+400", "nightly")
  end

  def test_the_build_suffix_is_optional_and_does_not_affect_the_patch
    [nil, "", "master", "nightly", "release", "release-ios", "release-macos"].each do |branch|
      assert_equal "1.2.1", marketing_version("1.2.1", branch)
      assert_equal "1.2.1", marketing_version("1.2.1+285", branch)
      assert_equal "1.2.1", marketing_version("1.2.1+999", branch)
    end
  end

  def test_a_version_it_cannot_read_fails_rather_than_guessing
    ["1.2", "1.2.1.1", "1.2.x", "", "v1.2.1", "-1.2.3", "1..3", "1.2.3-beta"].each do |value|
      [nil, "", "master", "nightly", "release"].each do |branch|
        output, error, status = run_script(value, branch)
        refute status.success?, "expected #{value.inspect} to be rejected on #{branch.inspect}"
        assert_empty output
        assert_includes error, "expected a numeric X.Y.Z version"
      end
    end
  end

  def test_the_version_argument_is_required
    _output, error, status = Open3.capture3("sh", SCRIPT, chdir: REPOSITORY)

    assert_equal 64, status.exitstatus
    assert_includes error, "usage:"
  end

  def test_both_post_clone_hooks_preserve_the_version_before_flutter_generation
    {
      "ios/ci_scripts/ci_post_clone.sh" => "XCODE_BUILD_NAME",
      "ci_scripts/macos_post_clone.sh" => "APP_VERSION"
    }.each do |path, variable|
      source = File.read(File.join(REPOSITORY, path))
      assignment = source[/^#{variable}="\$\(sh .*apple_marketing_version\.sh.*\n.*\)"$/]
      refute_nil assignment, "expected #{path} to call the shared version helper"
      assert_includes source, "--build-name=\"$#{variable}\""

      ["nightly", "master", "release-ios", "release-macos", ""].each do |branch|
        env = {
          "REPO" => REPOSITORY,
          "RAW_VERSION" => "12.34.56+789",
          "APP_BUILD_NAME" => "12.34.56",
          "CI_BRANCH" => "",
          "GITHUB_REF_NAME" => branch
        }
        output, error, status = Open3.capture3(
          env, "sh", "-eu", "-c", "#{assignment}\nprintf '%s\\n' \"$#{variable}\"",
          chdir: REPOSITORY
        )
        assert status.success?, error
        assert_equal "12.34.56\n", output, "#{path} on #{branch.inspect}"
      end
    end
  end

  def test_extra_arguments_are_rejected
    _output, error, status = Open3.capture3("sh", SCRIPT, "1.2.3", "nightly", "extra", chdir: REPOSITORY)

    assert_equal 64, status.exitstatus
    assert_includes error, "usage:"
  end

  private

  def marketing_version(value, branch = nil)
    output, error, status = run_script(value, branch)
    assert status.success?, error
    output.strip
  end

  def run_script(value, branch = nil)
    args = ["sh", SCRIPT, value]
    args << branch unless branch.nil?
    Open3.capture3(*args, chdir: REPOSITORY)
  end
end
