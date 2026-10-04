import Flutter
import MediaPlayer
import UIKit

/// Publishes the in-app music player to Control Center and the lock screen.
///
/// flutter_sound plays through AVAudioPlayer and never touches
/// MPNowPlayingInfoCenter, so without this the system shows no player even
/// though audio keeps playing in the background. Remote commands are sent
/// back to Dart, which owns the queue and playback state.
@MainActor
final class NowPlayingBridge {
  private let channel: FlutterMethodChannel
  private var commandTargets: [(MPRemoteCommand, Any)] = []
  private var artworkPath: String?
  private var artwork: MPMediaItemArtwork?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "mithka/now_playing", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      switch call.method {
      case "update":
        self.update(call.arguments as? [String: Any] ?? [:])
        result(nil)
      case "clear":
        self.clear()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func update(_ arguments: [String: Any]) {
    registerCommandsIfNeeded()
    let playing = arguments["playing"] as? Bool ?? false
    var info: [String: Any] = [
      MPMediaItemPropertyTitle: arguments["title"] as? String ?? "",
      MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
      MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0,
      MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
    ]
    if let artist = arguments["artist"] as? String, !artist.isEmpty {
      info[MPMediaItemPropertyArtist] = artist
    }
    if let album = arguments["album"] as? String, !album.isEmpty {
      info[MPMediaItemPropertyAlbumTitle] = album
    }
    if let duration = (arguments["durationMs"] as? NSNumber)?.doubleValue, duration > 0 {
      info[MPMediaItemPropertyPlaybackDuration] = duration / 1000
    }
    if let position = (arguments["positionMs"] as? NSNumber)?.doubleValue {
      info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = max(0, position / 1000)
    }
    if let artwork = loadArtwork(arguments["artworkPath"] as? String) {
      info[MPMediaItemPropertyArtwork] = artwork
    }
    // iOS derives playing/paused from the playback rate; `playbackState` is
    // macOS / Mac Catalyst only.
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
  }

  private func clear() {
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    for (command, target) in commandTargets {
      command.removeTarget(target)
    }
    commandTargets.removeAll()
    artworkPath = nil
    artwork = nil
  }

  private func loadArtwork(_ path: String?) -> MPMediaItemArtwork? {
    guard let path, !path.isEmpty else {
      artworkPath = nil
      artwork = nil
      return nil
    }
    if path == artworkPath { return artwork }
    artworkPath = path
    guard let image = UIImage(contentsOfFile: path) else {
      artwork = nil
      return nil
    }
    artwork = Self.makeArtwork(image)
    return artwork
  }

  /// MediaPlayer calls the artwork handler on its own queue. Building it
  /// outside the main actor keeps the closure free of main-actor isolation.
  private nonisolated static func makeArtwork(_ image: UIImage) -> MPMediaItemArtwork {
    MPMediaItemArtwork(boundsSize: image.size) { _ in image }
  }

  private func registerCommandsIfNeeded() {
    guard commandTargets.isEmpty else { return }
    let center = MPRemoteCommandCenter.shared()
    add(center.playCommand) { $0.send("play") }
    add(center.pauseCommand) { $0.send("pause") }
    add(center.togglePlayPauseCommand) { $0.send("toggle") }
    add(center.nextTrackCommand) { $0.send("next") }
    add(center.previousTrackCommand) { $0.send("previous") }
    let seek = center.changePlaybackPositionCommand
    seek.isEnabled = true
    let seekTarget = seek.addTarget { [weak self] event in
      // MediaPlayer delivers remote commands on the main thread.
      MainActor.assumeIsolated {
        guard let self, let event = event as? MPChangePlaybackPositionCommandEvent else {
          return .commandFailed
        }
        self.send("seek", Int(event.positionTime * 1000))
        return .success
      }
    }
    commandTargets.append((seek, seekTarget))
  }

  private func add(_ command: MPRemoteCommand, _ action: @escaping (NowPlayingBridge) -> Void) {
    command.isEnabled = true
    let target = command.addTarget { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return .commandFailed }
        action(self)
        return .success
      }
    }
    commandTargets.append((command, target))
  }

  private func send(_ method: String, _ arguments: Any? = nil) {
    channel.invokeMethod(method, arguments: arguments)
  }
}
