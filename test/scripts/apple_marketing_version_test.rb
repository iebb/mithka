# frozen_string_literal: true

require "minitest/autorun"
require "open3"

# The marketing version both Apple uploads carry. App Store Connect reviews a
# marketing version, not a build, so every nightly in a minor has to land on one
# train — 1.2.0 — and be told apart by its build number.
class AppleMarketingVersionTest < Minitest::Test
  SCRIPT = File.expand_path("../../scripts/apple_marketing_version.sh", __dir__)
  REPOSITORY = File.expand_path("../..", __dir__)

  def test_nightly_patches_collapse_onto_one_train
    assert_equal "1.2.0", marketing_version("1.2.1+285")
    assert_equal "1.2.0", marketing_version("1.2.7+291")
    assert_equal "1.2.0", marketing_version("1.2.0+285")
  end

  def test_a_new_minor_opens_a_new_train
    assert_equal "1.3.0", marketing_version("1.3.1+300")
    assert_equal "2.0.0", marketing_version("2.0.4+400")
  end

  def test_the_build_suffix_is_optional
    assert_equal "1.2.0", marketing_version("1.2.1")
  end

  def test_a_version_it_cannot_read_fails_rather_than_guessing
    ["1.2", "1.2.1.1", "1.2.x", "", "v1.2.1"].each do |value|
      _output, _error, status = run_script(value)
      refute status.success?, "expected #{value.inspect} to be rejected"
    end
  end

  def test_the_argument_is_required
    _output, _error, status = Open3.capture3("sh", SCRIPT, chdir: REPOSITORY)

    refute status.success?
  end

  private

  def marketing_version(value)
    output, error, status = run_script(value)
    assert status.success?, error
    output.strip
  end

  def run_script(value)
    Open3.capture3("sh", SCRIPT, value, chdir: REPOSITORY)
  end
end
