#!/usr/bin/env ruby
# frozen_string_literal: true

# Outputs only public release identities. Never serialize review details or keys.
require_relative "app_store_release"

module MithkaStoreReleaseState
  APP = MithkaAppStoreRelease::DEFAULT_APP_ID

  def self.all(client, path, params = {})
    data = []
    seen = []
    loop do
      key = [path, params]
      raise "pagination loop" if seen.include?(key)
      seen << key
      response = client.get(path, params)
      data.concat(response.fetch("data"))
      following = response.dig("links", "next")
      break unless following
      uri = URI(following)
      raise "unexpected pagination host" unless uri.scheme == "https" && uri.host == "api.appstoreconnect.apple.com" && uri.path.start_with?("/v1/")
      path = uri.path.delete_prefix("/v1")
      params = URI.decode_www_form(uri.query.to_s).to_h
    end
    data
  end

  def self.read(client, build_number: nil)
    app = client.get("/apps/#{APP}").fetch("data")
    raise "ASC app identity mismatch" unless app.dig("attributes", "bundleId") == "ad.neko.mithka"
    result = { "versions" => [], "trains" => [], "builds" => [] }
    all(client, "/apps/#{APP}/appStoreVersions", "limit" => "200", "include" => "build").each do |version|
      attrs = version.fetch("attributes")
      result["versions"] << {
        "id" => version.fetch("id"), "version" => attrs.fetch("versionString"),
        "platform" => attrs.fetch("platform"), "state" => attrs.fetch("appStoreState"),
        "build_id" => version.dig("relationships", "build", "data", "id")
      }
    end
    all(client, "/apps/#{APP}/preReleaseVersions", "limit" => "200").each do |train|
      result["trains"] << train.fetch("attributes").slice("version", "platform")
    end
    if build_number
      all(client, "/builds", "filter[app]" => APP, "filter[version]" => build_number, "limit" => "200").each do |build|
        train = client.get("/builds/#{build.fetch('id')}/preReleaseVersion").fetch("data").fetch("attributes")
        result["builds"] << build.fetch("attributes").slice("version", "processingState", "expired", "buildAudienceType").merge(
          "id" => build.fetch("id"), "platform" => train.fetch("platform"), "marketing_version" => train.fetch("version")
        )
      end
    end
    result
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    client = MithkaAppStoreRelease::Client.new(
      key_id: ENV.fetch("ASC_KEY_ID"), issuer_id: ENV.fetch("ASC_ISSUER_ID"), key_path: ENV.fetch("ASC_KEY_PATH")
    )
    puts JSON.generate(MithkaStoreReleaseState.read(client, build_number: ARGV.first))
  rescue StandardError => error
    # Provider responses can contain private metadata; expose only the class.
    status = error.respond_to?(:status) ? ", HTTP #{error.status}" : ""
    warn "Store state lookup failed (#{error.class}#{status})"
    exit 1
  end
end
