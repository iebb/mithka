# frozen_string_literal: true

require "minitest/autorun"

require_relative "../../scripts/distribute_testflight_groups"

class TestFlightGroupDistributorTest < Minitest::Test
  def setup
    @client = TestFlightGroupDistributor::Client.allocate
    @client.define_singleton_method(:token) { "test-token" }
  end

  def test_submission_limit_http_error_fails_the_workflow
    response = Struct.new(:code, :body).new(
      "422",
      JSON.generate("errors" => [{ "code" => "SUBMISSION_LIMIT_REACHED" }])
    )

    error = assert_raises(TestFlightGroupDistributor::Error) do
      Net::HTTP.stub(:start, stub_http(response)) do
        @client.post("/betaAppReviewSubmissions", "data" => [])
      end
    end

    assert_includes error.message, "SUBMISSION_LIMIT_REACHED"
  end

  def test_unrelated_http_error_still_fails
    response = Struct.new(:code, :body).new(
      "422",
      JSON.generate("errors" => [{
        "code" => "ENTITY_UNPROCESSABLE",
        "detail" => "Cannot add internal group to a build."
      }])
    )

    error = assert_raises(TestFlightGroupDistributor::Error) do
      Net::HTTP.stub(:start, stub_http(response)) do
        @client.post("/betaGroups/group/relationships/builds", "data" => [])
      end
    end

    assert_includes error.message, "ENTITY_UNPROCESSABLE"
  end

  def test_group_assignment_conflict_fails_instead_of_claiming_success
    response = Struct.new(:code, :body).new(
      "409",
      JSON.generate("errors" => [{ "code" => "STATE_ERROR" }])
    )

    error = assert_raises(TestFlightGroupDistributor::Error) do
      Net::HTTP.stub(:start, stub_http(response)) do
        @client.post("/betaGroups/group/relationships/builds", "data" => [])
      end
    end

    assert_includes error.message, "STATE_ERROR"
  end

  def test_runner_submits_external_review_and_verifies_both_groups
    posts = []
    client = Object.new
    client.define_singleton_method(:get) do |path, _params = {}|
      case path
      when "/builds"
        {
          "data" => [{
            "id" => "build",
            "attributes" => { "processingState" => "VALID" }
          }]
        }
      when "/builds/build/preReleaseVersion"
        { "data" => { "attributes" => { "platform" => "MAC_OS" } } }
      when "/apps/app/betaGroups"
        {
          "data" => [
            {
              "id" => "internal",
              "attributes" => {
                "name" => "Internal",
                "isInternalGroup" => true,
                "hasAccessToAllBuilds" => true
              }
            },
            {
              "id" => "external",
              "attributes" => {
                "name" => "External",
                "isInternalGroup" => false,
                "hasAccessToAllBuilds" => false
              }
            }
          ]
        }
      when "/betaAppReviewSubmissions"
        { "data" => [] }
      when "/builds/build/buildBetaDetail"
        {
          "data" => {
            "attributes" => {
              "internalBuildState" => "IN_BETA_TESTING",
              "externalBuildState" => "WAITING_FOR_BETA_REVIEW"
            }
          }
        }
      else
        raise "unexpected GET #{path}"
      end
    end
    client.define_singleton_method(:post) do |path, body|
      posts << [path, body]
      if path == "/betaAppReviewSubmissions"
        {
          "data" => {
            "attributes" => { "betaReviewState" => "WAITING_FOR_REVIEW" }
          }
        }
      else
        {}
      end
    end
    runner = TestFlightGroupDistributor::Runner.new(
      client: client,
      app_id: "app",
      build_number: "123",
      platform: "MAC_OS",
      internal_group: "Internal",
      external_group: "External",
      wait_seconds: 0,
      distribution_wait_seconds: 0
    )

    output, error = capture_io { runner.run }

    assert_empty error
    assert_equal "/betaGroups/external/relationships/builds", posts[0][0]
    assert_equal "/betaAppReviewSubmissions", posts[1][0]
    assert_equal "betaAppReviewSubmissions", posts[1][1].dig("data", "type")
    assert_equal "build", posts[1][1].dig("data", "relationships", "build", "data", "id")
    assert_includes output, "External: submitted to Beta App Review (WAITING_FOR_REVIEW)"
    assert_includes output, "Internal is IN_BETA_TESTING; External is WAITING_FOR_BETA_REVIEW"
  end

  def test_ready_to_submit_is_not_accepted_as_external_distribution
    client = Object.new
    client.define_singleton_method(:get) do |_path, _params = {}|
      {
        "data" => {
          "attributes" => {
            "internalBuildState" => "IN_BETA_TESTING",
            "externalBuildState" => "READY_FOR_BETA_SUBMISSION"
          }
        }
      }
    end
    runner = TestFlightGroupDistributor::Runner.new(
      client: client,
      app_id: "app",
      build_number: "123",
      platform: "MAC_OS",
      internal_group: "Internal",
      external_group: "External",
      wait_seconds: 0,
      distribution_wait_seconds: 0
    )

    error = assert_raises(TestFlightGroupDistributor::Error) do
      runner.send(:wait_for_distribution, "build")
    end

    assert_includes error.message, "External=READY_FOR_BETA_SUBMISSION"
  end

  def test_existing_beta_review_submission_is_idempotent
    client = Object.new
    client.define_singleton_method(:get) do |_path, _params = {}|
      {
        "data" => [{
          "attributes" => { "betaReviewState" => "WAITING_FOR_REVIEW" }
        }]
      }
    end
    client.define_singleton_method(:post) do |_path, _body|
      raise "should not create a duplicate Beta App Review submission"
    end
    runner = TestFlightGroupDistributor::Runner.new(
      client: client,
      app_id: "app",
      build_number: "123",
      platform: "MAC_OS",
      internal_group: "Internal",
      external_group: "External",
      wait_seconds: 0,
      distribution_wait_seconds: 0
    )

    state = nil
    output, error = capture_io do
      state = runner.send(:submit_external_review, "build")
    end

    assert_empty error
    assert_equal "WAITING_FOR_REVIEW", state
    assert_includes output, "External: Beta App Review already WAITING_FOR_REVIEW"
  end

  private

  def stub_http(response)
    http = Object.new
    http.define_singleton_method(:request) { |_request| response }
    lambda do |*_arguments, &block|
      block.call(http)
    end
  end
end
