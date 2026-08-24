# frozen_string_literal: true

require "minitest/autorun"
require "open3"

# The marketing version an Apple upload carries. App Store Connect reviews a
# marketing version, not a build, so every nightly in a minor has to land on one
# train — 1.2.0 — and be told apart by its build number. A release ships the
# exact version it is named for.
class AppleMarketingVersionTest < Minitest::Test
  SCRIPT = File.expand_path("../../scripts/apple_marketing_version.sh", __dir__)
  REPOSITORY = File.expand_path("../..", __dir__)

  def test_nightly_patches_collapse_onto_one_train
    assert_equal "1.2.0", marketing_version("1.2.1+285", "nightly")
    assert_equal "1.2.0", marketing_version("1.2.7+291", "nightly")
    assert_equal "1.2.0", marketing_version("1.2.0+285", "nightly")
  end

  def test_a_release_keeps_the_patch_it_ships
    assert_equal "1.1.2", marketing_version("1.1.2+284", "release")
    assert_equal "1.2.0", marketing_version("1.2.0+285", "release")
    # Per-platform release branches are release trains too.
    assert_equal "1.1.2", marketing_version("1.1.2+284", "release-ios")
    assert_equal "1.1.2", marketing_version("1.1.2+284", "release-macos/1.1")
    assert_equal "1.1.2", marketing_version("1.1.2+284", "release/1.1")
  end

  def test_anything_else_is_treated_as_a_nightly
    # The choice that cannot open an unintended review train.
    ["", "master", "codex/some-branch", "prerelease", "releases"].each do |branch|
      assert_equal "1.1.0", marketing_version("1.1.2+284", branch),
                   "expected #{branch.inspect} to use the nightly train"
    end
  end

  def test_a_new_minor_opens_a_new_train
    assert_equal "1.3.0", marketing_version("1.3.1+300", "nightly")
    assert_equal "2.0.0", marketing_version("2.0.4+400", "nightly")
  end

  def test_the_build_suffix_is_optional
    assert_equal "1.2.0", marketing_version("1.2.1", "nightly")
    assert_equal "1.2.1", marketing_version("1.2.1", "release")
  end

  def test_a_version_it_cannot_read_fails_rather_than_guessing
    ["1.2", "1.2.1.1", "1.2.x", "", "v1.2.1"].each do |value|
      ["nightly", "release"].each do |branch|
        _output, _error, status = run_script(value, branch)
        refute status.success?, "expected #{value.inspect} to be rejected on #{branch}"
      end
    end
  end

  def test_the_version_argument_is_required
    _output, _error, status = Open3.capture3("sh", SCRIPT, chdir: REPOSITORY)

    refute status.success?
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
