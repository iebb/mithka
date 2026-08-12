# frozen_string_literal: true

require "minitest/autorun"

require_relative "../../scripts/distribute_testflight_groups"

class TestFlightGroupDistributorTest < Minitest::Test
  def setup
    @client = TestFlightGroupDistributor::Client.allocate
    @client.define_singleton_method(:token) { "test-token" }
  end

  def test_submission_limit_http_error_returns_success_marker
    response = Struct.new(:code, :body).new(
      "422",
      JSON.generate("errors" => [{ "code" => "SUBMISSION_LIMIT_REACHED" }])
    )

    result = Net::HTTP.stub(:start, stub_http(response)) do
      @client.post("/betaGroups/group/relationships/builds", "data" => [])
    end

    assert_equal({ "submission_limit_reached" => true }, result)
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

  def test_submission_limit_error_code_is_recognized
    payload = {
      "errors" => [{
        "code" => "SUBMISSION_LIMIT_REACHED",
        "title" => "The request cannot be fulfilled because of the state of another resource."
      }]
    }

    assert @client.send(:submission_limit_reached?, payload)
  end

  def test_submission_limit_detail_is_recognized
    payload = {
      "errors" => [{
        "code" => "STATE_ERROR",
        "detail" => "The submission limit has been reached."
      }]
    }

    assert @client.send(:submission_limit_reached?, payload)
  end

  def test_unrelated_app_store_errors_are_not_recognized
    payload = {
      "errors" => [{
        "code" => "ENTITY_UNPROCESSABLE",
        "detail" => "Cannot add internal group to a build."
      }]
    }

    refute @client.send(:submission_limit_reached?, payload)
  end

  def test_runner_treats_submission_limit_result_as_success
    client = Object.new
    client.define_singleton_method(:post) do |_path, _body|
      { "submission_limit_reached" => true }
    end
    runner = TestFlightGroupDistributor::Runner.new(
      client: client,
      app_id: "app",
      build_number: "123",
      platform: "IOS",
      internal_group: "Internal",
      external_group: "External",
      wait_seconds: 0
    )
    group = {
      "id" => "group",
      "attributes" => {
        "name" => "External",
        "hasAccessToAllBuilds" => false
      }
    }

    result = nil
    output, error = capture_io { result = runner.send(:assign, "build", group) }

    assert_empty error
    assert_equal :submission_limit_reached, result
    assert_includes output, "submission limit reached; treating as success"
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
