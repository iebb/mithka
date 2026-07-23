import AVFoundation
import AVKit
import Flutter
import UIKit

/// Included iOS implementation of Mithka's shared system-PiP channel.
public final class SystemPictureInPicturePlugin: NSObject, FlutterPlugin,
  AVPictureInPictureControllerDelegate
{
  private let channel: FlutterMethodChannel
  private var player: AVPlayer?
  private var playerLayer: AVPlayerLayer?
  private var pictureInPictureController: AVPictureInPictureController?
  private var hostView: UIView?
  private var activeId: String?
  private var pendingStartResult: FlutterResult?
  private var startTimeout: DispatchWorkItem?
  private var possibleObservation: NSKeyValueObservation?
  private var statusObservation: NSKeyValueObservation?
  private var preferredRate: Float = 1.0

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = SystemPictureInPicturePlugin(messenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: instance.channel)
  }

  private init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "mithka/system_picture_in_picture",
      binaryMessenger: messenger
    )
    super.init()
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    DispatchQueue.main.async { [weak self] in
      self?.handleOnMain(call: call, result: result)
    }
  }

  private func handleOnMain(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isSupported":
      result(AVPictureInPictureController.isPictureInPictureSupported())
    case "prepare":
      result(prepare(call: call))
    case "startPrepared":
      startPrepared(call: call, result: result)
    case "update":
      update(call: call)
      result(nil)
    case "cancel":
      let id = (call.arguments as? [String: Any])?["id"] as? String
      if id == nil || id == activeId { stop(notifyFlutter: false) }
      result(nil)
    case "start":
      guard prepare(call: call) else {
        result(false)
        return
      }
      startPrepared(call: call, result: result)
    case "stop":
      stop()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func prepare(call: FlutterMethodCall) -> Bool {
    guard AVPictureInPictureController.isPictureInPictureSupported(),
      let args = call.arguments as? [String: Any],
      let id = args["id"] as? String,
      let rawURL = args["url"] as? String,
      let url = URL(string: rawURL)
    else { return false }

    stop(notifyFlutter: false)
    let audioSession = AVAudioSession.sharedInstance()
    try? audioSession.setCategory(.playback, mode: .moviePlayback)
    try? audioSession.setActive(true)

    let player = AVPlayer(playerItem: AVPlayerItem(url: url))
    applyPlaybackArguments(args, to: player, shouldSeek: true)
    guard let (layer, controller, hostView) = attach(player: player) else { return false }
    activeId = id
    self.player = player
    playerLayer = layer
    pictureInPictureController = controller
    self.hostView = hostView
    return true
  }

  private func startPrepared(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
      let id = args["id"] as? String,
      id == activeId,
      let player,
      let controller = pictureInPictureController
    else {
      result(false)
      return
    }
    applyPlaybackArguments(args, to: player, shouldSeek: true)
    beginStart(player: player, controller: controller, result: result)
  }

  private func update(call: FlutterMethodCall) {
    guard let args = call.arguments as? [String: Any],
      let id = args["id"] as? String,
      id == activeId,
      let player
    else { return }
    applyPlaybackArguments(args, to: player, shouldSeek: true)
  }

  private func applyPlaybackArguments(_ args: [String: Any], to player: AVPlayer, shouldSeek: Bool) {
    player.isMuted = args["muted"] as? Bool ?? false
    preferredRate = (args["speed"] as? NSNumber)?.floatValue ?? 1.0
    guard shouldSeek else { return }
    let positionMs = (args["positionMs"] as? NSNumber)?.doubleValue ?? 0
    guard positionMs > 0 else { return }
    let currentMs = player.currentTime().seconds * 1000
    if currentMs.isNaN || abs(currentMs - positionMs) > 750 {
      player.seek(
        to: CMTime(seconds: positionMs / 1000.0, preferredTimescale: 600),
        toleranceBefore: .zero,
        toleranceAfter: .zero
      )
    }
  }

  private func beginStart(
    player: AVPlayer,
    controller: AVPictureInPictureController,
    result: @escaping FlutterResult
  ) {
    clearStartObservers()
    pendingStartResult = result
    player.play()
    if preferredRate > 0, preferredRate != 1 { player.rate = preferredRate }

    let timeout = DispatchWorkItem { [weak self] in
      guard let self, self.pendingStartResult != nil else { return }
      self.pendingStartResult?(false)
      self.pendingStartResult = nil
      self.stop(notifyFlutter: false)
    }
    startTimeout = timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: timeout)

    possibleObservation = controller.observe(
      \.isPictureInPicturePossible,
      options: [.initial, .new]
    ) { [weak self, weak controller] _, _ in
      DispatchQueue.main.async {
        guard let self, let controller else { return }
        self.startIfPossible(controller)
      }
    }
    statusObservation = player.currentItem?.observe(
      \.status,
      options: [.initial, .new]
    ) { [weak self] item, _ in
      guard item.status == .failed else { return }
      DispatchQueue.main.async {
        self?.pendingStartResult?(false)
        self?.pendingStartResult = nil
        self?.stop(notifyFlutter: false)
      }
    }
  }

  private func startIfPossible(_ controller: AVPictureInPictureController) {
    guard pendingStartResult != nil,
      pictureInPictureController === controller,
      controller.isPictureInPicturePossible
    else { return }
    possibleObservation?.invalidate()
    possibleObservation = nil
    statusObservation?.invalidate()
    statusObservation = nil
    controller.startPictureInPicture()
  }

  private func clearStartObservers() {
    startTimeout?.cancel()
    startTimeout = nil
    possibleObservation?.invalidate()
    possibleObservation = nil
    statusObservation?.invalidate()
    statusObservation = nil
  }

  private func attach(player: AVPlayer) -> (AVPlayerLayer, AVPictureInPictureController, UIView)? {
    guard let root = Self.rootViewController() else { return nil }
    let host = UIView(frame: root.view.bounds)
    host.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    host.alpha = 0.01
    host.backgroundColor = .clear
    host.isUserInteractionEnabled = false
    let layer = AVPlayerLayer(player: player)
    layer.frame = host.bounds
    layer.videoGravity = .resizeAspect
    host.layer.addSublayer(layer)
    root.view.addSubview(host)
    guard let controller = AVPictureInPictureController(playerLayer: layer) else {
      host.removeFromSuperview()
      return nil
    }
    controller.delegate = self
    if #available(iOS 14.2, *) {
      controller.canStartPictureInPictureAutomaticallyFromInline = true
    }
    return (layer, controller, host)
  }

  private func stop(notifyFlutter: Bool = true) {
    clearStartObservers()
    pendingStartResult?(false)
    pendingStartResult = nil
    let stoppedId = activeId
    player?.pause()
    if pictureInPictureController?.isPictureInPictureActive == true {
      pictureInPictureController?.stopPictureInPicture()
    }
    pictureInPictureController?.delegate = nil
    pictureInPictureController = nil
    playerLayer?.player = nil
    playerLayer?.removeFromSuperlayer()
    playerLayer = nil
    hostView?.removeFromSuperview()
    hostView = nil
    player = nil
    activeId = nil
    preferredRate = 1
    if notifyFlutter, let stoppedId {
      channel.invokeMethod("didStop", arguments: ["id": stoppedId])
    }
  }

  public func pictureInPictureControllerDidStartPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    DispatchQueue.main.async { [weak self] in
      self?.clearStartObservers()
      self?.pendingStartResult?(true)
      self?.pendingStartResult = nil
    }
  }

  public func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    failedToStartPictureInPictureWithError error: Error
  ) {
    DispatchQueue.main.async { [weak self] in
      self?.pendingStartResult?(false)
      self?.pendingStartResult = nil
      self?.stop(notifyFlutter: false)
    }
  }

  public func pictureInPictureControllerDidStopPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    DispatchQueue.main.async { [weak self] in self?.stop() }
  }

  public func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
  ) {
    completionHandler(false)
  }

  private static func rootViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    return topViewController(from: scene?.windows.first { $0.isKeyWindow }?.rootViewController)
  }

  private static func topViewController(from root: UIViewController?) -> UIViewController? {
    if let nav = root as? UINavigationController { return topViewController(from: nav.visibleViewController) }
    if let tab = root as? UITabBarController { return topViewController(from: tab.selectedViewController) }
    if let presented = root?.presentedViewController { return topViewController(from: presented) }
    return root
  }
}
