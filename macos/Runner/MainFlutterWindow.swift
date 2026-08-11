import AVFoundation
import AVKit
import Cocoa
import FlutterMacOS
import multi_window_manager

class MainFlutterWindow: NSWindow {
  /// Native RunnerTests are application-hosted so they can exercise the real
  /// AppDelegate and primary window. Starting Flutter here would also start
  /// TDLib, whose native worker threads outlive XCTest's abrupt host teardown
  /// and can abort while C++ statics are being destroyed.
  static func isNativeTestHost(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    isXCTestLoaded: Bool = NSClassFromString("XCTestCase") != nil
  ) -> Bool {
    environment["XCTestConfigurationFilePath"] != nil || isXCTestLoaded
  }

  /// Closing or minimizing the primary window hides it in the menu bar while
  /// its Flutter engine and background services continue running.
  override func close() {
    orderOut(nil)
  }

  override func miniaturize(_ sender: Any?) {
    orderOut(sender)
  }

  override func awakeFromNib() {
    let windowFrame = self.frame
    if Self.isNativeTestHost() {
      contentViewController = NSViewController()
      setFrame(windowFrame, display: true)
      super.awakeFromNib()
      configurePrimaryWindow()
      return
    }

    let flutterViewController = FlutterViewController()
    // Bind the termination channel before attaching the controller (and before
    // Dart can start TDLib). Child engines created below never register it.
    ApplicationTerminationBridge.shared.registerPrimary(
      viewController: flutterViewController
    )
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    MacOSAppIconPlugin.register(
      with: flutterViewController.registrar(forPlugin: "MacOSAppIconPlugin")
    )
    HandoffBridge.shared.register(
      messenger: flutterViewController.engine.binaryMessenger
    )
    DesktopClipboardImagesPlugin.register(
      with: flutterViewController.registrar(forPlugin: "DesktopClipboardImagesPlugin")
    )
    MacOSSystemPictureInPicturePlugin.register(
      with: flutterViewController.registrar(
        forPlugin: "MacOSSystemPictureInPicturePlugin"
      )
    )
    MultiWindowManagerPlugin.RegisterGeneratedPlugins = { registry in
      RegisterGeneratedPlugins(registry: registry)
      MacOSAppIconPlugin.register(
        with: registry.registrar(forPlugin: "MacOSAppIconPlugin")
      )
      DesktopClipboardImagesPlugin.register(
        with: registry.registrar(forPlugin: "DesktopClipboardImagesPlugin")
      )
      MacOSSystemPictureInPicturePlugin.register(
        with: registry.registrar(
          forPlugin: "MacOSSystemPictureInPicturePlugin"
        )
      )
    }

    super.awakeFromNib()

    configurePrimaryWindow()
  }

  private func configurePrimaryWindow() {
    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    styleMask.insert(.fullSizeContentView)
    isReleasedWhenClosed = false
    minSize = NSSize(width: 820, height: 560)
    if #available(macOS 11.0, *) {
      titlebarSeparatorStyle = .none
    }
  }
}

private final class DesktopClipboardImagesPlugin: NSObject, FlutterPlugin {
  private static let gif = NSPasteboard.PasteboardType("com.compuserve.gif")
  private static let jpeg = NSPasteboard.PasteboardType("public.jpeg")
  private static let webp = NSPasteboard.PasteboardType("org.webmproject.webp")
  private static let heic = NSPasteboard.PasteboardType("public.heic")
  private static let heif = NSPasteboard.PasteboardType("public.heif")

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "mithka/clipboard",
      binaryMessenger: registrar.messenger
    )
    let instance = DesktopClipboardImagesPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "readImages" else {
      result(FlutterMethodNotImplemented)
      return
    }
    result(Self.readImages())
  }

  private static func readImages() -> [[String: Any]] {
    guard let items = NSPasteboard.general.pasteboardItems else { return [] }
    return items.compactMap(readImage)
  }

  private static func readImage(_ item: NSPasteboardItem) -> [String: Any]? {
    if
      let value = item.string(forType: .fileURL),
      let url = URL(string: value),
      url.isFileURL,
      let payload = readImageFile(url)
    {
      return payload
    }

    let representations: [(NSPasteboard.PasteboardType, String)] = [
      (gif, "image/gif"),
      (.png, "image/png"),
      (jpeg, "image/jpeg"),
      (webp, "image/webp"),
      (heic, "image/heic"),
      (heif, "image/heif"),
    ]
    for (type, mimeType) in representations {
      if let data = item.data(forType: type), !data.isEmpty {
        return payload(data, mimeType: mimeType)
      }
    }
    guard
      let tiff = item.data(forType: .tiff),
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]),
      !png.isEmpty
    else {
      return nil
    }
    return payload(png, mimeType: "image/png")
  }

  private static func readImageFile(_ url: URL) -> [String: Any]? {
    let mimeType: String
    switch url.pathExtension.lowercased() {
    case "jpg", "jpeg": mimeType = "image/jpeg"
    case "png": mimeType = "image/png"
    case "gif": mimeType = "image/gif"
    case "webp": mimeType = "image/webp"
    case "heic": mimeType = "image/heic"
    case "heif": mimeType = "image/heif"
    default: return nil
    }
    guard let data = try? Data(contentsOf: url), !data.isEmpty else {
      return nil
    }
    return payload(data, mimeType: mimeType)
  }

  private static func payload(_ data: Data, mimeType: String) -> [String: Any] {
    return [
      "mimeType": mimeType,
      "data": FlutterStandardTypedData(bytes: data),
    ]
  }
}

/// A transparent, hit-test-free host keeps AVPlayerLayer attached to the
/// current Flutter window while AVKit owns the system Picture-in-Picture UI.
private final class MacOSPictureInPictureHostView: NSView {
  var playerLayer: AVPlayerLayer?

  override func layout() {
    super.layout()
    playerLayer?.frame = bounds
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    return nil
  }
}

/// Native macOS implementation of Mithka's shared system-PiP method channel.
///
/// The Flutter player uses a texture backend, so AVKit cannot adopt its layer
/// directly. This bridge creates a synchronized AVPlayer for the same local
/// stream, hands that player's layer to AVPictureInPictureController, and
/// reports the final playback position when PiP closes or restores.
private final class MacOSSystemPictureInPicturePlugin: NSObject, FlutterPlugin,
  AVPictureInPictureControllerDelegate
{
  private let channel: FlutterMethodChannel
  private weak var rootView: NSView?
  private var player: AVPlayer?
  private var playerLayer: AVPlayerLayer?
  private var pictureInPictureController: AVPictureInPictureController?
  private var hostView: MacOSPictureInPictureHostView?
  private var activeId: String?
  private var pendingStartResult: FlutterResult?
  private var startTimeout: DispatchWorkItem?
  private var possibleObservation: NSKeyValueObservation?
  private var statusObservation: NSKeyValueObservation?
  private var preferredRate: Float = 1
  private var preferredPlaying = true
  private var restoreAccepted = false

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = MacOSSystemPictureInPicturePlugin(registrar: registrar)
    registrar.addMethodCallDelegate(instance, channel: instance.channel)
  }

  private init(registrar: FlutterPluginRegistrar) {
    channel = FlutterMethodChannel(
      name: "mithka/system_picture_in_picture",
      binaryMessenger: registrar.messenger
    )
    rootView = registrar.view
    super.init()
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    DispatchQueue.main.async { [weak self] in
      self?.handleOnMain(call, result: result)
    }
  }

  private func handleOnMain(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    switch call.method {
    case "isSupported":
      result(AVPictureInPictureController.isPictureInPictureSupported())
    case "prepare":
      result(prepare(call))
    case "startPrepared":
      startPrepared(call, result: result)
    case "update":
      update(call)
      result(nil)
    case "cancel":
      let id = (call.arguments as? [String: Any])?["id"] as? String
      if id == nil || id == activeId { stop(notifyFlutter: false) }
      result(nil)
    case "start":
      guard prepare(call) else {
        result(false)
        return
      }
      startPrepared(call, result: result)
    case "stop":
      stop()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func prepare(_ call: FlutterMethodCall) -> Bool {
    guard
      AVPictureInPictureController.isPictureInPictureSupported(),
      let arguments = call.arguments as? [String: Any],
      let id = arguments["id"] as? String,
      let rawURL = arguments["url"] as? String,
      let url = URL(string: rawURL)
    else {
      return false
    }

    let replacingSession = activeId != nil && activeId != id
    stop(notifyFlutter: replacingSession)
    let player = AVPlayer(playerItem: AVPlayerItem(url: url))
    applyPlaybackArguments(arguments, to: player, shouldSeek: true)
    guard let attachment = attach(player: player) else { return false }
    activeId = id
    self.player = player
    playerLayer = attachment.layer
    pictureInPictureController = attachment.controller
    hostView = attachment.host
    return true
  }

  private func startPrepared(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    guard
      let arguments = call.arguments as? [String: Any],
      let id = arguments["id"] as? String,
      id == activeId,
      let player,
      let controller = pictureInPictureController
    else {
      result(false)
      return
    }
    applyPlaybackArguments(arguments, to: player, shouldSeek: true)
    beginStart(player: player, controller: controller, result: result)
  }

  private func update(_ call: FlutterMethodCall) {
    guard
      let arguments = call.arguments as? [String: Any],
      let id = arguments["id"] as? String,
      id == activeId,
      let player
    else {
      return
    }
    applyPlaybackArguments(arguments, to: player, shouldSeek: true)
    applyPreferredPlaybackState(to: player)
  }

  private func applyPlaybackArguments(
    _ arguments: [String: Any],
    to player: AVPlayer,
    shouldSeek: Bool
  ) {
    player.isMuted = arguments["muted"] as? Bool ?? false
    preferredRate = (arguments["speed"] as? NSNumber)?.floatValue ?? 1
    preferredPlaying = arguments["playing"] as? Bool ?? true
    guard shouldSeek else { return }
    let positionMs = (arguments["positionMs"] as? NSNumber)?.doubleValue ?? 0
    let currentMs = player.currentTime().seconds * 1000
    if positionMs > 0, !currentMs.isFinite || abs(currentMs - positionMs) > 750 {
      player.seek(
        to: CMTime(seconds: positionMs / 1000, preferredTimescale: 600),
        toleranceBefore: .zero,
        toleranceAfter: .zero
      )
    }
  }

  private func applyPreferredPlaybackState(to player: AVPlayer) {
    if preferredPlaying {
      player.play()
      if preferredRate > 0, preferredRate != 1 { player.rate = preferredRate }
    } else {
      player.pause()
    }
  }

  private func beginStart(
    player: AVPlayer,
    controller: AVPictureInPictureController,
    result: @escaping FlutterResult
  ) {
    clearStartObservers()
    pendingStartResult = result
    applyPreferredPlaybackState(to: player)

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
    guard
      pendingStartResult != nil,
      pictureInPictureController === controller,
      controller.isPictureInPicturePossible
    else {
      return
    }
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

  private func attach(
    player: AVPlayer
  ) -> (
    layer: AVPlayerLayer,
    controller: AVPictureInPictureController,
    host: MacOSPictureInPictureHostView
  )? {
    guard let rootView else { return nil }
    let host = MacOSPictureInPictureHostView(frame: rootView.bounds)
    host.autoresizingMask = [.width, .height]
    host.wantsLayer = true
    host.alphaValue = 0.01
    let layer = AVPlayerLayer(player: player)
    layer.frame = host.bounds
    layer.videoGravity = .resizeAspect
    host.playerLayer = layer
    host.layer?.addSublayer(layer)
    rootView.addSubview(host, positioned: .below, relativeTo: nil)
    guard let controller = AVPictureInPictureController(playerLayer: layer)
    else {
      host.removeFromSuperview()
      return nil
    }
    controller.delegate = self
    return (layer, controller, host)
  }

  private func stop(notifyFlutter: Bool = true) {
    clearStartObservers()
    pendingStartResult?(false)
    pendingStartResult = nil
    let stoppedId = activeId
    let stoppedPositionMs = positionMilliseconds(player)
    let wasRestored = restoreAccepted
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
    preferredPlaying = true
    restoreAccepted = false
    if notifyFlutter, let stoppedId {
      channel.invokeMethod(
        "didStop",
        arguments: [
          "id": stoppedId,
          "positionMs": stoppedPositionMs,
          "restored": wasRestored,
        ]
      )
    }
  }

  func pictureInPictureControllerDidStartPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    DispatchQueue.main.async { [weak self] in
      self?.clearStartObservers()
      self?.pendingStartResult?(true)
      self?.pendingStartResult = nil
    }
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    failedToStartPictureInPictureWithError error: Error
  ) {
    DispatchQueue.main.async { [weak self] in
      self?.pendingStartResult?(false)
      self?.pendingStartResult = nil
      self?.stop(notifyFlutter: false)
    }
  }

  func pictureInPictureControllerDidStopPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    DispatchQueue.main.async { [weak self] in self?.stop() }
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler
      completionHandler: @escaping (Bool) -> Void
  ) {
    guard let activeId, let player else {
      completionHandler(false)
      return
    }
    let requestedId = activeId
    var completed = false
    let finish: (Bool) -> Void = { [weak self] restored in
      guard !completed else { return }
      completed = true
      let validSession = self?.activeId == requestedId
      let accepted = restored && validSession
      if validSession { self?.restoreAccepted = accepted }
      completionHandler(accepted)
    }
    let timeout = DispatchWorkItem { finish(false) }
    DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: timeout)
    channel.invokeMethod(
      "restoreRequested",
      arguments: [
        "id": requestedId,
        "positionMs": positionMilliseconds(player),
        "playing": player.timeControlStatus != .paused,
        "speed": preferredRate,
        "muted": player.isMuted,
      ]
    ) { response in
      DispatchQueue.main.async {
        timeout.cancel()
        finish((response as? NSNumber)?.boolValue ?? false)
      }
    }
  }

  private func positionMilliseconds(_ player: AVPlayer?) -> Int64 {
    guard let seconds = player?.currentTime().seconds, seconds.isFinite else {
      return 0
    }
    return Int64(max(0, (seconds * 1000).rounded()))
  }
}
