# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../scripts/store_release_state"

class StoreReleaseStateTest < Minitest::Test
  class Client
    def initialize(routes)
      @routes = routes
    end

    def get(path, params = {})
      @routes.fetch([path, params]) { @routes.fetch(path) }
    end
  end

  def test_state_export_excludes_review_and_credential_fields
    client = Client.new(
      "/apps/6783830742" => { "data" => { "attributes" => { "bundleId" => "ad.neko.mithka" } } },
      "/apps/6783830742/appStoreVersions" => { "data" => [{ "id" => "listing", "attributes" => { "versionString" => "1.8.8", "platform" => "IOS", "appStoreState" => "WAITING_FOR_REVIEW", "privateValue" => "DO_NOT_EXPORT" }, "relationships" => { "build" => { "data" => { "id" => "build" } } } }] },
      "/apps/6783830742/preReleaseVersions" => { "data" => [{ "attributes" => { "version" => "1.8.8", "platform" => "IOS", "privateValue" => "DO_NOT_EXPORT" } }] }
    )
    result = MithkaStoreReleaseState.read(client)
    assert_equal "build", result["versions"].first["build_id"]
    refute_includes JSON.generate(result), "DO_NOT_EXPORT"
  end

  def test_pagination_follows_only_the_real_asc_origin
    client = Client.new(
      "/page" => { "data" => [1], "links" => { "next" => "https://api.appstoreconnect.apple.com/v1/page2?cursor=next" } },
      ["/page2", { "cursor" => "next" }] => { "data" => [2] }
    )
    assert_equal [1, 2], MithkaStoreReleaseState.all(client, "/page")
    bad = Client.new("/page" => { "data" => [], "links" => { "next" => "https://other.example/v1/page" } })
    assert_raises(RuntimeError) { MithkaStoreReleaseState.all(bad, "/page") }
  end

  def test_different_app_identity_is_refused
    client = Client.new("/apps/6783830742" => { "data" => { "attributes" => { "bundleId" => "wrong" } } })
    assert_raises(RuntimeError) { MithkaStoreReleaseState.read(client) }
  end
end
