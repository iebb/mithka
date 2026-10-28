#!/usr/bin/env ruby
# frozen_string_literal: true

require "pathname"
require_relative "app_store_release"

module MithkaAppStoreWorkflow
  class Error < StandardError; end

  def self.source_version(source_commit, command_runner: Open3.method(:capture3))
    raise Error, "source commit must be a full SHA" unless source_commit.match?(/\A[0-9a-f]{40}\z/)

    result, _error, status = command_runner.call(
      "gh", "api", "repos/iebb/mithka/contents/pubspec.yaml?ref=#{source_commit}"
    )
    raise Error, "could not verify the source version through GitHub" unless status.success?

    data = JSON.parse(result)
    raise Error, "source pubspec must be base64 encoded" unless data["encoding"] == "base64"

    pubspec = Base64.strict_decode64(data.fetch("content").gsub(/\s/, ""))
    version = pubspec[/^version:\s*([0-9]+\.[0-9]+\.[0-9]+)(?:\+[0-9]+)?\s*$/, 1]
    raise Error, "source pubspec has no normal X.Y.Z version" unless version

    version
  end

  def self.verify_source_version!(version, source_commit, reader: method(:source_version))
    normal_version = reader.call(source_commit)
    unless version == normal_version
      raise Error, "store version must preserve the source patch: expected #{normal_version}"
    end
  end

  def self.arguments(env, root: File.expand_path("..", __dir__))
    unless env["GITHUB_REPOSITORY"] == "iebb/mithka" &&
           env["GITHUB_REF"] == "refs/heads/master" &&
           env["GITHUB_EVENT_NAME"] == "workflow_dispatch"
      raise Error, "App Review dispatch must run from iebb/mithka master"
    end
    operation = env.fetch("STORE_OPERATION")
    raise Error, "operation must be validate or submit" unless %w[validate submit].include?(operation)

    notes = env.fetch("STORE_RELEASE_NOTES_PATH")
    path = Pathname.new(notes)
    if path.absolute? || path.each_filename.include?("..") || path.extname != ".json"
      raise Error, "release notes must be a JSON file under distribution/app-store"
    end
    notes_root = File.realpath(File.join(root, "distribution/app-store"))
    notes_path = File.realpath(File.join(root, notes))
    unless notes_path.start_with?("#{notes_root}/") && File.file?(notes_path)
      raise Error, "release notes must remain within distribution/app-store"
    end

    version = env.fetch("STORE_VERSION")
    binary_version = env["STORE_BINARY_VERSION"].to_s.strip
    args = [
      "--platform", env.fetch("STORE_PLATFORM"),
      "--version", version,
      "--binary-version", binary_version.empty? ? version : binary_version,
      "--build-number", env.fetch("STORE_BUILD_NUMBER"),
      "--source-commit", env.fetch("STORE_SOURCE_COMMIT"),
      "--release-notes-json", notes_path,
      "--key-id", env.fetch("ASC_KEY_ID"),
      "--issuer-id", env.fetch("ASC_ISSUER_ID"),
      "--key-path", env.fetch("ASC_KEY_PATH"),
      "--wait-seconds", "600", "--submit"
    ]
    case env.fetch("STORE_PROVENANCE")
    when "github_actions"
      build_id = env["STORE_UPLOADED_BUILD_ID"].to_s
      raise Error, "GitHub Actions provenance requires the ASC build UUID" if build_id.empty?

      args.concat(["--github-run-id", env.fetch("STORE_BUILD_RUN_ID"), "--uploaded-build-id", build_id])
    when "xcode_cloud"
      unless env["STORE_UPLOADED_BUILD_ID"].to_s.empty?
        raise Error, "Xcode Cloud provenance must not include an uploaded build UUID"
      end
      args.concat(["--ci-build-run-id", env.fetch("STORE_BUILD_RUN_ID")])
    else
      raise Error, "unsupported build provenance"
    end
    args << "--apply" if operation == "submit"
    args
  end

  def self.run(env = ENV)
    args = arguments(env)
    verify_source_version!(env.fetch("STORE_VERSION"), env.fetch("STORE_SOURCE_COMMIT"))
    MithkaAppStoreRelease.cli(args)
  rescue Error, KeyError, Errno::ENOENT, JSON::ParserError, ArgumentError => error
    warn "error: #{error.message}"
    1
  end
end

exit(MithkaAppStoreWorkflow.run) if $PROGRAM_NAME == __FILE__
