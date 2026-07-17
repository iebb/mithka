import AVFoundation
import Flutter
import UIKit

private final class TelegramCallEventStream: NSObject, FlutterStreamHandler {
  private var sink: FlutterEventSink?

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }

  func emit(_ event: [String: Any]) {
    DispatchQueue.main.async { [weak self] in
      self?.sink?(event)
    }
  }
}

#if canImport(TgVoipWebrtc)
import TgVoipWebrtc

private final class TelegramGroupCallQueue: NSObject, OngoingCallThreadLocalContextQueueWebrtc {
  private let queue = DispatchQueue(label: "ad.neko.mithka.group-call", qos: .userInitiated)
  private let key = DispatchSpecificKey<Void>()

  override init() {
    super.init()
    queue.setSpecific(key: key, value: ())
  }

  func dispatch(_ block: @escaping () -> Void) {
    queue.async(execute: block)
  }

  func dispatch(after seconds: Double, block: @escaping () -> Void) {
    queue.asyncAfter(deadline: .now() + seconds, execute: block)
  }

  func isCurrent() -> Bool {
    DispatchQueue.getSpecific(key: key) != nil
  }

  func scheduleBlock(_ block: @escaping () -> Void, after timeout: Double) -> GroupCallDisposable {
    let work = DispatchWorkItem(block: block)
    queue.asyncAfter(deadline: .now() + timeout, execute: work)
    return GroupCallDisposable { work.cancel() }
  }
}

private final class EmptyBroadcastTask: NSObject, OngoingGroupCallBroadcastPartTask {
  func cancel() {}
}

private final class EmptyMediaDescriptionTask: NSObject, OngoingGroupCallMediaChannelDescriptionTask {
  func cancel() {}
}
#endif

@MainActor
final class TelegramGroupCallMediaBridge: NSObject {
  private let channel: FlutterMethodChannel
  private let eventChannel: FlutterEventChannel
  private let eventStream = TelegramCallEventStream()
  private var audioSessionIsActive: Bool

#if canImport(TgVoipWebrtc)
  private let contextQueue = TelegramGroupCallQueue()
  private var context: GroupCallThreadLocalContext?
  private var videoCapturer: OngoingCallThreadLocalContextVideoCapturer?
  private var audioDevice: SharedCallAudioDevice?
  private var p2pContext: OngoingCallThreadLocalContextWebrtc?
  private var p2pVideoCapturer: OngoingCallThreadLocalContextVideoCapturer?
  private var p2pAudioDevice: SharedCallAudioDevice?
  private weak var localVideoContainer: UIView?
  private let mediaDescriptionsLock = NSLock()
  private var mediaDescriptionsBySsrc: [UInt32: OngoingGroupCallMediaChannelDescription] = [:]
#endif

  init(
    messenger: FlutterBinaryMessenger,
    registrar: FlutterApplicationRegistrar,
    audioSessionManagedBySystem: Bool
  ) {
    channel = FlutterMethodChannel(name: "mithka/call_media", binaryMessenger: messenger)
    eventChannel = FlutterEventChannel(
      name: "mithka/call_media/events",
      binaryMessenger: messenger
    )
    audioSessionIsActive = !audioSessionManagedBySystem
    super.init()
    eventChannel.setStreamHandler(eventStream)
    channel.setMethodCallHandler { [weak self] call, result in
      Task { @MainActor in
        self?.handle(call: call, result: result)
      }
    }
    registrar.register(
      TelegramGroupVideoViewFactory(bridge: self),
      withId: "mithka/group_video_view"
    )
    registrar.register(
      TelegramGroupVideoViewFactory(bridge: self),
      withId: "mithka/video_view"
    )
  }

  func setAudioSessionActive(_ active: Bool) {
    audioSessionIsActive = active
#if canImport(TgVoipWebrtc)
    context?.setManualAudioSessionIsActive(active)
    audioDevice?.setManualAudioSessionIsActive(active)
    p2pContext?.setManualAudioSessionIsActive(active)
    p2pAudioDevice?.setManualAudioSessionIsActive(active)
#endif
  }

  fileprivate func attachVideo(role: String, to container: UIView) {
#if canImport(TgVoipWebrtc)
    if role == "local" {
      localVideoContainer = container
    }
    let completion: ((UIView & OngoingCallThreadLocalContextWebrtcVideoView)?) -> Void = { view in
      DispatchQueue.main.async {
        container.subviews.forEach { $0.removeFromSuperview() }
        guard let view else { return }
        let fittedView = TelegramAspectFitVideoView(videoView: view)
        fittedView.frame = container.bounds
        fittedView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(fittedView)
      }
    }
    if role == "local" {
      p2pVideoCapturer?.makeOutgoingVideoView(false) { view, _ in completion(view) }
    } else if role == "remote" {
      p2pContext?.makeIncomingVideoView { view in completion(view) }
    } else if role == "group:local" {
      videoCapturer?.makeOutgoingVideoView(false) { view, _ in completion(view) }
    } else if role.hasPrefix("group:") {
      let endpointId = String(role.dropFirst("group:".count))
      context?.makeIncomingVideoView(
        withEndpointId: endpointId,
        requestClone: false
      ) { view, _ in completion(view) }
    }
#endif
  }

#if canImport(TgVoipWebrtc)
  private func refreshLocalVideoPreview() {
    guard let localVideoContainer else { return }
    attachVideo(role: "local", to: localVideoContainer)
  }
#endif

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getProtocol":
#if canImport(TgVoipWebrtc)
      // Telegram iOS reverses the framework's raw version list before it is
      // advertised. The resulting order is the local preference order used
      // when choosing the first version also supported by the peer.
      let versions = Array(
        OngoingCallThreadLocalContextWebrtc
          .versions(withIncludeReference: false)
          .reversed()
      )
      result([
        "min": 65,
        "max": Int(OngoingCallThreadLocalContextWebrtc.maxLayer()),
        "versions": versions,
      ])
#else
      result(FlutterMethodNotImplemented)
#endif
    case "start":
      startP2P(call: call, result: result)
    case "receiveSignaling":
#if canImport(TgVoipWebrtc)
      if let data = (call.arguments as? FlutterStandardTypedData)?.data {
        p2pContext?.addSignaling(data)
      }
#endif
      result(nil)
    case "isSupported":
#if canImport(TgVoipWebrtc)
      result(true)
#else
      result(false)
#endif
    case "createGroup":
      createGroup(call: call, result: result)
    case "connectGroup":
      connectGroup(call: call, result: result)
    case "stop":
      stop()
      result(nil)
    case "setMuted":
#if canImport(TgVoipWebrtc)
      let muted = call.arguments as? Bool ?? false
      p2pContext?.setIsMuted(muted)
      context?.setIsMuted(muted)
#endif
      result(nil)
    case "setSpeaker":
      setSpeaker(call.arguments as? Bool ?? true, result: result)
    case "setVideoEnabled":
      setVideoEnabled(call: call, result: result)
    case "switchCamera":
#if canImport(TgVoipWebrtc)
      let activeCapturer = p2pVideoCapturer ?? videoCapturer
      let useFront = !(activeCapturer.map { _ in currentCameraIsFront } ?? true)
      currentCameraIsFront = useFront
      activeCapturer?.switchVideoInput(useFront ? "" : "back")
#endif
      result(nil)
    case "setRequestedVideoChannels":
      setRequestedVideoChannels(call.arguments)
      result(nil)
    case "setMediaChannelDescriptions":
      setMediaChannelDescriptions(call.arguments)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

#if canImport(TgVoipWebrtc)
  private var currentCameraIsFront = true
#endif

  private func startP2P(call: FlutterMethodCall, result: @escaping FlutterResult) {
#if canImport(TgVoipWebrtc)
    guard
      let arguments = call.arguments as? [String: Any],
      let config = arguments["config"] as? [String: Any],
      let key = (config["encryptionKey"] as? FlutterStandardTypedData)?.data,
      key.count == 256,
      let version = (config["libraryVersions"] as? [String])?.first
    else {
      result(
        FlutterError(
          code: "invalid_p2p_config",
          message: "The Telegram call media configuration is incomplete",
          details: nil
        )
      )
      return
    }

    let isOutgoing = config["isOutgoing"] as? Bool ?? false
    let isVideo = config["isVideo"] as? Bool ?? false
    let preparedVideoCapturer = isVideo ? p2pVideoCapturer : nil
    stop()
    let allowP2P = config["p2pAllowed"] as? Bool ?? true
    let maxLayer = (config["maxLayer"] as? NSNumber)?.int32Value
      ?? OngoingCallThreadLocalContextWebrtc.maxLayer()
    let rawServers = config["servers"] as? [[String: Any]] ?? []
    let reflectorIds = rawServers.compactMap { server -> Int64? in
      guard server["peerTag"] is FlutterStandardTypedData else { return nil }
      return (server["id"] as? NSNumber)?.int64Value
    }.sorted()
    var reflectorIdMapping: [Int64: UInt8] = [:]
    for (index, id) in Array(Set(reflectorIds)).sorted().enumerated() where index < 255 {
      reflectorIdMapping[id] = UInt8(index + 1)
    }
    let connections = rawServers.flatMap {
      p2pConnections(from: $0, reflectorIdMapping: reflectorIdMapping)
    }
    guard !connections.isEmpty else {
      result(
        FlutterError(
          code: "missing_p2p_servers",
          message: "Telegram did not provide a usable call relay",
          details: nil
        )
      )
      return
    }

    OngoingCallThreadLocalContextWebrtc.applyServerConfig(
      config["serverConfig"] as? String
    )
    let capturer = isVideo
      ? preparedVideoCapturer
        ?? OngoingCallThreadLocalContextVideoCapturer(deviceId: "", keepLandscape: false)
      : nil
    let device = SharedCallAudioDevice(disableRecording: false, enableSystemMute: false)
    let logBase = (NSTemporaryDirectory() as NSString).appendingPathComponent("mithka-p2p-call")
    let eventStream = self.eventStream
    let context = OngoingCallThreadLocalContextWebrtc(
      version: version,
      customParameters: config["customParameters"] as? String,
      queue: contextQueue,
      proxy: nil,
      networkType: .wifi,
      dataSaving: .never,
      derivedState: Data(),
      key: key,
      isOutgoing: isOutgoing,
      connections: connections,
      maxLayer: maxLayer,
      allowP2P: allowP2P,
      allowTCP: true,
      enableStunMarking: false,
      logPath: "\(logBase).log",
      statsLogPath: "\(logBase)-stats.json",
      sendSignalingData: { [weak eventStream] data in
        eventStream?.emit([
          "type": "signaling",
          "data": FlutterStandardTypedData(bytes: data),
        ])
      },
      videoCapturer: capturer,
      preferredVideoCodec: nil,
      audioInputDeviceId: "",
      audioDevice: device,
      directConnection: nil
    )
    context.stateChanged = { [weak eventStream] state, _, _, _, _, _ in
      let value: String
      switch state {
      case .initializing: value = "CONNECTING"
      case .connected: value = "CONNECTED"
      case .failed: value = "FAILED"
      case .reconnecting: value = "RECONNECTING"
      @unknown default: value = "UNKNOWN"
      }
      eventStream?.emit(["type": "state", "state": value])
    }
    p2pVideoCapturer = capturer
    refreshLocalVideoPreview()
    p2pAudioDevice = device
    p2pContext = context
    context.setManualAudioSessionIsActive(audioSessionIsActive)
    device.setManualAudioSessionIsActive(audioSessionIsActive)
    result(nil)
#else
    result(
      FlutterError(
        code: "tgvoip_webrtc_missing",
        message: "This build does not contain Telegram's TgVoipWebrtc framework",
        details: nil
      )
    )
#endif
  }

#if canImport(TgVoipWebrtc)
  private func p2pConnections(
    from server: [String: Any],
    reflectorIdMapping: [Int64: UInt8]
  ) -> [OngoingCallConnectionDescriptionWebrtc] {
    let rawId = (server["id"] as? NSNumber)?.int64Value ?? 0
    let peerTag = (server["peerTag"] as? FlutterStandardTypedData)?.data
    let isReflector = peerTag != nil
    let reflectorId = isReflector ? reflectorIdMapping[rawId] ?? 0 : 0
    let hasStun = isReflector ? false : server["stun"] as? Bool ?? false
    let hasTurn = isReflector ? true : server["turn"] as? Bool ?? false
    let hasTcp = server["tcp"] as? Bool ?? false
    let username = isReflector ? "reflector" : server["username"] as? String ?? ""
    let password = isReflector ? hex(peerTag ?? Data()) : server["password"] as? String ?? ""
    let port = (server["port"] as? NSNumber)?.int32Value ?? 0
    let addresses = [server["ipv4"] as? String, server["ipv6"] as? String]
      .compactMap { $0 }
      .filter { !$0.isEmpty }
    return addresses.map {
      OngoingCallConnectionDescriptionWebrtc(
        reflectorId: reflectorId,
        hasStun: hasStun,
        hasTurn: hasTurn,
        hasTcp: hasTcp,
        ip: $0,
        port: port,
        username: username,
        password: password
      )
    }
  }

  private func hex(_ data: Data) -> String {
    data.map { String(format: "%02x", $0) }.joined()
  }
#endif

  private func createGroup(call: FlutterMethodCall, result: @escaping FlutterResult) {
#if canImport(TgVoipWebrtc)
    stop()
    let arguments = call.arguments as? [String: Any]
    let isVideo = arguments?["isVideo"] as? Bool ?? false
    currentCameraIsFront = true
    videoCapturer = isVideo
      ? OngoingCallThreadLocalContextVideoCapturer(deviceId: "", keepLandscape: false)
      : nil
    let device = SharedCallAudioDevice(disableRecording: false, enableSystemMute: false)
    audioDevice = device
    let logBase = (NSTemporaryDirectory() as NSString).appendingPathComponent("mithka-group-call")
    let context = GroupCallThreadLocalContext(
      queue: contextQueue,
      networkStateUpdated: { _ in },
      audioLevelsUpdated: { _ in },
      activityUpdated: { _ in },
      inputDeviceId: "",
      outputDeviceId: "",
      videoCapturer: videoCapturer,
      requestMediaChannelDescriptions: { [weak self] ssrcs, completion in
        guard let self else {
          completion([])
          return EmptyMediaDescriptionTask()
        }
        self.mediaDescriptionsLock.lock()
        let descriptions = ssrcs.compactMap {
          self.mediaDescriptionsBySsrc[$0.uint32Value]
        }
        self.mediaDescriptionsLock.unlock()
        completion(descriptions)
        return EmptyMediaDescriptionTask()
      },
      requestCurrentTime: { completion in
        completion(0)
        return EmptyBroadcastTask()
      },
      requestAudioBroadcastPart: { _, _, _ in EmptyBroadcastTask() },
      requestVideoBroadcastPart: { _, _, _, _, _ in EmptyBroadcastTask() },
      outgoingAudioBitrateKbit: 32,
      videoContentType: isVideo ? .generic : .none,
      enableNoiseSuppression: true,
      disableAudioInput: false,
      enableSystemMute: false,
      prioritizeVP8: false,
      logPath: "\(logBase).log",
      statsLogPath: "\(logBase)-stats.json",
      onMutedSpeechActivityDetected: nil,
      audioDevice: device,
      isConference: false,
      isActiveByDefault: audioSessionIsActive,
      encryptDecrypt: nil,
      useReferenceImpl: false
    )
    self.context = context
    context.setManualAudioSessionIsActive(audioSessionIsActive)
    device.setManualAudioSessionIsActive(audioSessionIsActive)
    context.emitJoinPayload { payload, ssrc in
      DispatchQueue.main.async {
        result(["audioSourceId": Int64(ssrc), "payload": payload])
      }
    }
#else
    result(
      FlutterError(
        code: "tgvoip_webrtc_missing",
        message: "This build does not contain Telegram's TgVoipWebrtc framework",
        details: nil
      )
    )
#endif
  }

  private func connectGroup(call: FlutterMethodCall, result: @escaping FlutterResult) {
#if canImport(TgVoipWebrtc)
    guard
      let arguments = call.arguments as? [String: Any],
      let payload = arguments["responsePayload"] as? String,
      let context
    else {
      result(FlutterError(code: "group_call_not_created", message: nil, details: nil))
      return
    }
    context.setConnectionMode(
      .rtc,
      keepBroadcastConnectedIfWasEnabled: false,
      isUnifiedBroadcast: false
    )
    context.setJoinResponsePayload(payload)
    result(nil)
#else
    result(FlutterError(code: "tgvoip_webrtc_missing", message: nil, details: nil))
#endif
  }

  private func setVideoEnabled(call: FlutterMethodCall, result: @escaping FlutterResult) {
#if canImport(TgVoipWebrtc)
    let arguments = call.arguments as? [String: Any]
    let enabled = arguments?["enabled"] as? Bool ?? false
    currentCameraIsFront = arguments?["front"] as? Bool ?? true
    if let p2pContext {
      if enabled {
        let capturer = p2pVideoCapturer
          ?? OngoingCallThreadLocalContextVideoCapturer(deviceId: "", keepLandscape: false)
        capturer.switchVideoInput(currentCameraIsFront ? "" : "back")
        p2pVideoCapturer = capturer
        p2pContext.requestVideo(capturer)
      } else {
        p2pContext.disableVideo()
        p2pVideoCapturer = nil
      }
      result(nil)
      return
    }
    if context == nil {
      if enabled {
        let capturer = p2pVideoCapturer
          ?? OngoingCallThreadLocalContextVideoCapturer(deviceId: "", keepLandscape: false)
        capturer.switchVideoInput(currentCameraIsFront ? "" : "back")
        p2pVideoCapturer = capturer
        refreshLocalVideoPreview()
      } else {
        p2pVideoCapturer = nil
      }
      result(nil)
      return
    }
    guard let context else {
      result(FlutterError(code: "group_call_not_created", message: nil, details: nil))
      return
    }
    let completion: (String, UInt32) -> Void = { payload, ssrc in
      DispatchQueue.main.async {
        result(["audioSourceId": Int64(ssrc), "payload": payload])
      }
    }
    if enabled {
      let capturer = videoCapturer
        ?? OngoingCallThreadLocalContextVideoCapturer(deviceId: "", keepLandscape: false)
      capturer.switchVideoInput(currentCameraIsFront ? "" : "back")
      videoCapturer = capturer
      context.requestVideo(capturer, completion: completion)
    } else {
      context.disableVideo { [weak self] payload, ssrc in
        DispatchQueue.main.async {
          self?.videoCapturer = nil
          result(["audioSourceId": Int64(ssrc), "payload": payload])
        }
      }
    }
#else
    result(FlutterError(code: "tgvoip_webrtc_missing", message: nil, details: nil))
#endif
  }

  private func setRequestedVideoChannels(_ rawArguments: Any?) {
#if canImport(TgVoipWebrtc)
    let rawChannels = rawArguments as? [[String: Any]] ?? []
    let channels = rawChannels.compactMap { raw -> OngoingGroupCallRequestedVideoChannel? in
      guard
        let audioSource = raw["audioSourceId"] as? NSNumber,
        let userId = raw["userId"] as? NSNumber,
        let endpointId = raw["endpointId"] as? String
      else { return nil }
      let groups: [OngoingGroupCallSsrcGroup] = (
        raw["sourceGroups"] as? [[String: Any]] ?? []
      ).compactMap { group -> OngoingGroupCallSsrcGroup? in
        guard
          let semantics = group["semantics"] as? String,
          let sourceIds = group["sourceIds"] as? [NSNumber]
        else { return nil }
        return OngoingGroupCallSsrcGroup(semantics: semantics, ssrcs: sourceIds)
      }
      return OngoingGroupCallRequestedVideoChannel(
        audioSsrc: audioSource.uint32Value,
        userId: userId.int64Value,
        endpointId: endpointId,
        ssrcGroups: groups,
        minQuality: quality(raw["minQuality"] as? String),
        maxQuality: quality(raw["maxQuality"] as? String)
      )
    }
    context?.setRequestedVideoChannels(channels)
#endif
  }

  private func setMediaChannelDescriptions(_ rawArguments: Any?) {
#if canImport(TgVoipWebrtc)
    let rawDescriptions = rawArguments as? [[String: Any]] ?? []
    var descriptions: [UInt32: OngoingGroupCallMediaChannelDescription] = [:]
    for raw in rawDescriptions {
      guard
        let audioSource = raw["audioSourceId"] as? NSNumber,
        let userId = raw["userId"] as? NSNumber
      else { continue }
      let ssrc = audioSource.uint32Value
      descriptions[ssrc] = OngoingGroupCallMediaChannelDescription(
        type: .audio,
        peerId: userId.int64Value,
        audioSsrc: ssrc,
        videoDescription: nil
      )
    }
    mediaDescriptionsLock.lock()
    mediaDescriptionsBySsrc = descriptions
    mediaDescriptionsLock.unlock()
#endif
  }

#if canImport(TgVoipWebrtc)
  private func quality(_ value: String?) -> OngoingGroupCallRequestedVideoQuality {
    switch value {
    case "medium": return .medium
    case "full": return .full
    default: return .thumbnail
    }
  }
#endif

  private func setSpeaker(_ enabled: Bool, result: @escaping FlutterResult) {
    do {
      try AVAudioSession.sharedInstance().overrideOutputAudioPort(enabled ? .speaker : .none)
      result(nil)
    } catch {
      result(FlutterError(code: "audio_route_failed", message: error.localizedDescription, details: nil))
    }
  }

  private func stop() {
#if canImport(TgVoipWebrtc)
    p2pContext?.beginTermination()
    p2pContext?.stop(nil)
    p2pContext = nil
    p2pVideoCapturer = nil
    p2pAudioDevice = nil
    context?.stop(nil)
    context = nil
    videoCapturer = nil
    audioDevice = nil
    mediaDescriptionsLock.lock()
    mediaDescriptionsBySsrc.removeAll()
    mediaDescriptionsLock.unlock()
#endif
  }
}

#if canImport(TgVoipWebrtc)
@MainActor
private final class TelegramAspectFitVideoView: UIView {
  private let videoView: UIView & OngoingCallThreadLocalContextWebrtcVideoView
  private var videoAspect: CGFloat

  init(videoView: UIView & OngoingCallThreadLocalContextWebrtcVideoView) {
    self.videoView = videoView
    videoAspect = videoView.aspect > 0.01 ? videoView.aspect : 16.0 / 9.0
    super.init(frame: .zero)
    backgroundColor = .black
    clipsToBounds = true
    addSubview(videoView)
    videoView.setOnOrientationUpdated { [weak self] _, aspect in
      DispatchQueue.main.async {
        guard let self, aspect > 0.01 else { return }
        self.videoAspect = aspect
        self.setNeedsLayout()
      }
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    guard bounds.width > 0, bounds.height > 0, videoAspect > 0 else {
      videoView.frame = bounds
      return
    }
    videoView.frame = AVMakeRect(
      aspectRatio: CGSize(width: videoAspect, height: 1.0),
      insideRect: bounds
    ).integral
  }
}
#endif

@MainActor
private final class TelegramGroupVideoViewFactory: NSObject, FlutterPlatformViewFactory {
  private weak var bridge: TelegramGroupCallMediaBridge?

  init(bridge: TelegramGroupCallMediaBridge) {
    self.bridge = bridge
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    let role = (args as? [String: Any])?["role"] as? String ?? ""
    return TelegramGroupVideoPlatformView(frame: frame, role: role, bridge: bridge)
  }
}

@MainActor
private final class TelegramGroupVideoPlatformView: NSObject, FlutterPlatformView {
  private let container: UIView

  init(frame: CGRect, role: String, bridge: TelegramGroupCallMediaBridge?) {
    container = UIView(frame: frame)
    container.backgroundColor = .black
    super.init()
    bridge?.attachVideo(role: role, to: container)
  }

  func view() -> UIView {
    container
  }
}
