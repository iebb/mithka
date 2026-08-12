# frozen_string_literal: true

require "minitest/autorun"
require "open3"

class AppleCiBuildNumberTest < Minitest::Test
  OFFSET = 0
  SCRIPT = File.expand_path("../../scripts/apple_ci_build_number.sh", __dir__)
  REPOSITORY = File.expand_path("../..", __dir__)

  def test_build_number_is_commit_height
    height = git("rev-list", "--count", "HEAD").to_i

    output, error, status = Open3.capture3("sh", SCRIPT, "HEAD", chdir: REPOSITORY)

    assert status.success?, error
    assert_equal OFFSET + height, Integer(output, 10)
  end

  def test_older_commit_has_a_smaller_build_number
    current = build_number("HEAD")
    parent = build_number("HEAD^")

    assert_equal 1, current - parent
  end

  def test_unknown_commit_fails
    _output, error, status = Open3.capture3("sh", SCRIPT, "not-a-commit", chdir: REPOSITORY)

    refute status.success?
    assert_includes error, "unknown revision"
  end

  private

  def build_number(commit)
    output, error, status = Open3.capture3("sh", SCRIPT, commit, chdir: REPOSITORY)
    raise error unless status.success?

    Integer(output, 10)
  end

  def git(*arguments)
    output, error, status = Open3.capture3("git", *arguments, chdir: REPOSITORY)
    raise error unless status.success?

    output
  end
end
