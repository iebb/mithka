import AVFoundation
import AVKit
import Flutter
import ImageIO
import LiveCommunicationKit
import Security
import Sentry
import SwiftUI
import Translation
import UIKit

@main
@MainActor
@objc class AppDelegate: FlutterAppDelegate, @preconcurrency FlutterImplicitEngineDelegate {
  private var nativeTranslationBridge: AnyObject?
  private var pushChannel: FlutterMethodChannel?
  private var apnsDeviceToken: String?
  private var didRegisterFlutterPlugins = false
  private var systemPictureInPictureBridge: SystemPictureInPictureBridge?
  private var liveCommunicationBridge: AnyObject?
  private var groupCallMediaBridge: TelegramGroupCallMediaBridge?
  private var mediaDropBridge: MediaDropBridge?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    configureNativeSentryIfNeeded()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func configureNativeSentryIfNeeded() {
    guard !SentrySDK.isEnabled else { return }
    let info = Bundle.main.infoDictionary ?? [:]
    let encodedDsn = (info["SentryDSNEncoded"] as? String ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let dsn = (encodedDsn.removingPercentEncoding ?? encodedDsn)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !dsn.isEmpty, !dsn.contains("$(") else { return }

    let configuredEnvironment = (info["SentryEnvironment"] as? String ?? "production")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let environment = configuredEnvironment.isEmpty || configuredEnvironment.contains("$(")
      ? "production"
      : configuredEnvironment

    SentrySDK.start { options in
      options.dsn = dsn
      options.environment = environment
      options.releaseName = Self.sentryReleaseName(info: info)
      options.sendDefaultPii = false
      options.tracesSampleRate = 0.0
      options.enableWatchdogTerminationTracking = true
    }
  }

  private static func sentryReleaseName(info: [String: Any]) -> String {
    let bundleId = info["CFBundleIdentifier"] as? String ?? "ad.neko.mithka"
    let version = info["CFBundleShortVersionString"] as? String ?? "0"
    let build = info["CFBundleVersion"] as? String ?? "0"
    return "\(bundleId)@\(version)+\(build)"
  }

  private static func nativeIconName(_ name: String) -> String? {
    switch name {
    case "white": return "MithkaWhite"
    case "blue": return "MithkaBlue"
    case "purple": return "MithkaPurple"
    case "pixel": return "MithkaPixel"
    default: return nil
    }
  }

  private static func flutterIconName(_ name: String?) -> String {
    switch name {
    case "MithkaWhite": return "white"
    case "MithkaBlue": return "blue"
    case "MithkaPurple": return "purple"
    case "MithkaPixel": return "pixel"
    default: return "default"
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    // Flutter creates the implicit engine before FlutterViewController runs it.
    // Some plugins send an initial platform message during registration, so
    // register after the engine has had a chance to launch on the main loop.
    DispatchQueue.main.async { [weak self] in
      self?.registerFlutterPluginsAndChannels(engineBridge)
    }
  }

  private func registerFlutterPluginsAndChannels(_ engineBridge: FlutterImplicitEngineBridge) {
    guard !didRegisterFlutterPlugins else { return }
    didRegisterFlutterPlugins = true
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let clipboardChannel = FlutterMethodChannel(
      name: "mithka/clipboard",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    clipboardChannel.setMethodCallHandler { call, result in
      guard call.method == "readImage" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let pasteboard = UIPasteboard.general
      if let data = pasteboard.data(forPasteboardType: "com.compuserve.gif") {
        result(["mimeType": "image/gif", "data": FlutterStandardTypedData(bytes: data)])
        return
      }
      if let data = pasteboard.data(forPasteboardType: "public.png") {
        result(["mimeType": "image/png", "data": FlutterStandardTypedData(bytes: data)])
        return
      }
      if let data = pasteboard.data(forPasteboardType: "public.jpeg") {
        result(["mimeType": "image/jpeg", "data": FlutterStandardTypedData(bytes: data)])
        return
      }
      if let image = pasteboard.image, let data = image.pngData() {
        result(["mimeType": "image/png", "data": FlutterStandardTypedData(bytes: data)])
        return
      }
      result(nil)
    }
    let animatedAvatarChannel = FlutterMethodChannel(
      name: "mithka/animated_avatar",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    animatedAvatarChannel.setMethodCallHandler { call, result in
      guard call.method == "prepare" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let arguments = call.arguments as? [String: Any],
        let inputPath = arguments["path"] as? String,
        !inputPath.isEmpty
      else {
        result(
          FlutterError(
            code: "invalid_arguments",
            message: "An animated image path is required",
            details: nil
          )
        )
        return
      }
      let callback = AnimatedAvatarFlutterCallback(result)
      let crop = AnimatedAvatarCropRegion(
        left: arguments["cropLeft"] as? Double ?? 0,
        top: arguments["cropTop"] as? Double ?? 0,
        width: arguments["cropWidth"] as? Double ?? 1,
        height: arguments["cropHeight"] as? Double ?? 1
      )
      AnimatedAvatarTranscoder.transcode(inputPath: inputPath, crop: crop) { conversion in
        switch conversion {
        case .success(let outputPath):
          callback.success(outputPath)
        case .failure(let error):
          callback.failure(error)
        }
      }
    }
    mediaDropBridge = MediaDropBridge(
      messenger: engineBridge.applicationRegistrar.messenger()
    )

    let fontsChannel = FlutterMethodChannel(
      name: "mithka/fonts",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    fontsChannel.setMethodCallHandler { call, result in
      if call.method == "normalizeFontFamilies" {
        let values = call.arguments as? [String] ?? []
        result(values.map { value in
          if let font = UIFont(name: value, size: UIFont.systemFontSize) {
            return font.familyName
          }
          return value
        })
        return
      }
      guard call.method == "listFonts" else {
        result(FlutterMethodNotImplemented)
        return
      }
      var names = Set<String>()
      UIFont.familyNames.forEach { family in
        names.insert(family)
      }
      result(Array(names).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
    }

    let appIconChannel = FlutterMethodChannel(
      name: "mithka/app_icon",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    appIconChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "isSupported":
        result(UIApplication.shared.supportsAlternateIcons)
      case "currentIcon":
        result(Self.flutterIconName(UIApplication.shared.alternateIconName))
      case "setIcon":
        guard UIApplication.shared.supportsAlternateIcons else {
          result(
            FlutterError(
              code: "unsupported_platform",
              message: "Alternate app icons are not supported on this device",
              details: nil
            )
          )
          return
        }
        let args = call.arguments as? [String: Any]
        let requested = args?["name"] as? String ?? "default"
        let nativeName = Self.nativeIconName(requested)
        UIApplication.shared.setAlternateIconName(nativeName) { error in
          if let error {
            result(
              FlutterError(
                code: "app_icon_failed",
                message: error.localizedDescription,
                details: nil
              )
            )
            return
          }
          result(nil)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let wakelockChannel = FlutterMethodChannel(
      name: "mithka/screen_wakelock",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    wakelockChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "enable":
        UIApplication.shared.isIdleTimerDisabled = true
        result(nil)
      case "disable":
        UIApplication.shared.isIdleTimerDisabled = false
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let playerBrightnessChannel = FlutterMethodChannel(
      name: "mithka/player_brightness",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    playerBrightnessChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "get":
        result(Double(UIScreen.main.brightness))
      case "set":
        guard let value = call.arguments as? NSNumber else {
          result(FlutterError(code: "invalid_brightness", message: "Expected a numeric value", details: nil))
          return
        }
        UIScreen.main.brightness = CGFloat(max(0.01, min(1, value.doubleValue)))
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let accountBackupChannel = FlutterMethodChannel(
      name: "mithka/account_backup",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    let accountBackup = AccountSessionBackupKeychain()
    accountBackupChannel.setMethodCallHandler { call, result in
      accountBackup.handle(call: call, result: result)
    }

    let pushChannel = FlutterMethodChannel(
      name: "mithka/push",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    self.pushChannel = pushChannel
    pushChannel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "registerForRemoteNotifications" else {
        result(FlutterMethodNotImplemented)
        return
      }
      UIApplication.shared.registerForRemoteNotifications()
      result(self?.apnsDeviceToken)
    }

    let systemPiPBridge = SystemPictureInPictureBridge(
      messenger: engineBridge.applicationRegistrar.messenger()
    )
    systemPictureInPictureBridge = systemPiPBridge

    var liveCommunicationOwnsAudioSession = false
    if #available(iOS 17.4, *) {
      liveCommunicationOwnsAudioSession = true
    }
    let groupCallMediaBridge = TelegramGroupCallMediaBridge(
      messenger: engineBridge.applicationRegistrar.messenger(),
      registrar: engineBridge.applicationRegistrar,
      audioSessionManagedBySystem: liveCommunicationOwnsAudioSession
    )
    self.groupCallMediaBridge = groupCallMediaBridge

    if #available(iOS 17.4, *) {
      liveCommunicationBridge = LiveCommunicationBridge(
        messenger: engineBridge.applicationRegistrar.messenger(),
        audioSessionChanged: { [weak groupCallMediaBridge] active in
          groupCallMediaBridge?.setAudioSessionActive(active)
        }
      )
    } else {
      let liveCommunicationChannel = FlutterMethodChannel(
        name: "mithka/live_communication",
        binaryMessenger: engineBridge.applicationRegistrar.messenger()
      )
      liveCommunicationChannel.setMethodCallHandler { call, result in
        switch call.method {
        case "start", "connected", "setMuted", "updateMembers", "end":
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    let nativeTranslationChannel = FlutterMethodChannel(
      name: "mithka/native_translation",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    if #available(iOS 18.0, *) {
      let bridge = NativeTranslationBridge()
      nativeTranslationBridge = bridge
      bridge.attachHostIfNeeded()
      nativeTranslationChannel.setMethodCallHandler { call, result in
        if call.method == "capabilities" {
          result(["ios_system"])
          return
        }
        bridge.handle(call: call, result: result)
      }
    } else {
      nativeTranslationChannel.setMethodCallHandler { call, result in
        if call.method == "capabilities" {
          result([])
          return
        }
        guard call.method == "translate" else {
          result(FlutterMethodNotImplemented)
          return
        }
        result(
          FlutterError(
            code: "unsupported_platform",
            message: "本机翻译需要 iOS 18 或更高版本",
            details: nil
          )
        )
      }
    }
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    let token = deviceToken.map { String(format: "%02x", $0) }.joined()
    apnsDeviceToken = token
    pushChannel?.invokeMethod("deviceToken", arguments: token)
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    pushChannel?.invokeMethod("registrationError", arguments: error.localizedDescription)
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }
}

private final class AnimatedAvatarFlutterCallback: @unchecked Sendable {
  private let result: FlutterResult

  init(_ result: @escaping FlutterResult) {
    self.result = result
  }

  func success(_ outputPath: String) {
    DispatchQueue.main.async { [self] in result(outputPath) }
  }

  func failure(_ error: Error) {
    DispatchQueue.main.async { [self] in
      result(
        FlutterError(
          code: "animated_avatar_conversion_failed",
          message: error.localizedDescription,
          details: nil
        )
      )
    }
  }
}

private enum AnimatedAvatarTranscodeError: LocalizedError {
  case unreadableImage
  case missingFrames
  case cannotCreateWriter
  case cannotStartWriter
  case cannotCreatePixelBuffer
  case cannotAppendFrame
  case exportFailed(String)

  var errorDescription: String? {
    switch self {
    case .unreadableImage: return "The selected animated image could not be decoded"
    case .missingFrames: return "The selected image does not contain animation frames"
    case .cannotCreateWriter: return "The profile video encoder could not be created"
    case .cannotStartWriter: return "The profile video encoder could not start"
    case .cannotCreatePixelBuffer: return "An animation frame could not be prepared"
    case .cannotAppendFrame: return "An animation frame could not be encoded"
    case .exportFailed(let reason): return "Profile video export failed: \(reason)"
    }
  }
}

private struct AnimatedAvatarCropRegion: Sendable {
  let left: Double
  let top: Double
  let width: Double
  let height: Double

  var clamped: AnimatedAvatarCropRegion {
    let safeWidth = min(max(width, 0.001), 1)
    let safeHeight = min(max(height, 0.001), 1)
    return AnimatedAvatarCropRegion(
      left: min(max(left, 0), 1 - safeWidth),
      top: min(max(top, 0), 1 - safeHeight),
      width: safeWidth,
      height: safeHeight
    )
  }
}

private enum AnimatedAvatarTranscoder {
  private static let queue = DispatchQueue(
    label: "ad.neko.mithka.animated-avatar",
    qos: .userInitiated
  )
  private static let maximumDuration = 10.0
  private static let defaultFrameDuration = 0.1
  private static let minimumFrameDuration = 0.02
  private static let maximumDimension = 640

  static func transcode(
    inputPath: String,
    crop: AnimatedAvatarCropRegion,
    completion: @escaping @Sendable (Result<String, Error>) -> Void
  ) {
    queue.async {
      do {
        let outputPath = try transcodeSynchronously(
          inputPath: inputPath,
          crop: crop.clamped
        )
        completion(.success(outputPath))
      } catch {
        completion(.failure(error))
      }
    }
  }

  private static func transcodeSynchronously(
    inputPath: String,
    crop: AnimatedAvatarCropRegion
  ) throws -> String {
    let inputURL = URL(fileURLWithPath: inputPath)
    if let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
       CGImageSourceGetCount(source) > 1
    {
      return try transcodeAnimatedImage(source: source, crop: crop)
    }
    return try transcodeVideo(inputURL: inputURL, crop: crop)
  }

  private static func transcodeAnimatedImage(
    source: CGImageSource,
    crop: AnimatedAvatarCropRegion
  ) throws -> String {
    let frameCount = CGImageSourceGetCount(source)
    guard frameCount > 1, let firstFrame = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
      throw AnimatedAvatarTranscodeError.missingFrames
    }

    let cropPixelSide = max(
      Double(firstFrame.width) * crop.width,
      Double(firstFrame.height) * crop.height
    )
    var side = min(max(Int(cropPixelSide.rounded()), 2), maximumDimension)
    if side % 2 != 0 { side -= 1 }
    side = max(side, 2)

    let outputURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("mithka-avatar-\(UUID().uuidString).mp4")
    try? FileManager.default.removeItem(at: outputURL)

    let writer: AVAssetWriter
    do {
      writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
    } catch {
      throw AnimatedAvatarTranscodeError.cannotCreateWriter
    }
    let outputSettings: [String: Any] = [
      AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: side,
      AVVideoHeightKey: side,
      AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: max(300_000, side * side * 4),
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
      ],
    ]
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: input,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: side,
        kCVPixelBufferHeightKey as String: side,
        kCVPixelBufferIOSurfacePropertiesKey as String: [:],
      ]
    )
    guard writer.canAdd(input) else {
      throw AnimatedAvatarTranscodeError.cannotCreateWriter
    }
    writer.add(input)
    guard writer.startWriting() else {
      throw AnimatedAvatarTranscodeError.cannotStartWriter
    }
    writer.startSession(atSourceTime: .zero)

    var timestamp = 0.0
    for index in 0..<frameCount {
      guard timestamp < maximumDuration else { break }
      guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
      while !input.isReadyForMoreMediaData {
        if writer.status == .failed || writer.status == .cancelled {
          throw AnimatedAvatarTranscodeError.exportFailed(
            writer.error?.localizedDescription ?? "encoder stopped"
          )
        }
        Thread.sleep(forTimeInterval: 0.002)
      }
      guard
        let pool = adaptor.pixelBufferPool,
        let pixelBuffer = makePixelBuffer(
          image: image,
          side: side,
          crop: crop,
          pool: pool
        )
      else {
        throw AnimatedAvatarTranscodeError.cannotCreatePixelBuffer
      }
      let presentationTime = CMTime(seconds: timestamp, preferredTimescale: 600)
      guard adaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
        throw AnimatedAvatarTranscodeError.cannotAppendFrame
      }
      timestamp += min(frameDuration(source: source, index: index), maximumDuration - timestamp)
    }
    guard timestamp > 0 else {
      throw AnimatedAvatarTranscodeError.missingFrames
    }

    input.markAsFinished()
    let semaphore = DispatchSemaphore(value: 0)
    writer.finishWriting { semaphore.signal() }
    semaphore.wait()
    guard writer.status == .completed else {
      throw AnimatedAvatarTranscodeError.exportFailed(
        writer.error?.localizedDescription ?? "unknown encoder error"
      )
    }
    return outputURL.path
  }

  private static func transcodeVideo(
    inputURL: URL,
    crop: AnimatedAvatarCropRegion
  ) throws -> String {
    let asset = AVURLAsset(url: inputURL)
    guard let track = asset.tracks(withMediaType: .video).first else {
      throw AnimatedAvatarTranscodeError.unreadableImage
    }
    let transformedBounds = CGRect(origin: .zero, size: track.naturalSize)
      .applying(track.preferredTransform)
      .standardized
    guard transformedBounds.width > 0, transformedBounds.height > 0 else {
      throw AnimatedAvatarTranscodeError.unreadableImage
    }
    let cropPixelSide = max(
      transformedBounds.width * CGFloat(crop.width),
      transformedBounds.height * CGFloat(crop.height)
    )
    var side = min(max(Int(cropPixelSide.rounded()), 2), maximumDimension)
    if side % 2 != 0 { side -= 1 }
    side = max(side, 2)

    let reader = try AVAssetReader(asset: asset)
    let readerOutput = AVAssetReaderTrackOutput(
      track: track,
      outputSettings: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
      ]
    )
    readerOutput.alwaysCopiesSampleData = false
    guard reader.canAdd(readerOutput) else {
      throw AnimatedAvatarTranscodeError.cannotCreateWriter
    }
    reader.add(readerOutput)

    let outputURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("mithka-avatar-\(UUID().uuidString).mp4")
    try? FileManager.default.removeItem(at: outputURL)
    let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
    let writerInput = AVAssetWriterInput(
      mediaType: .video,
      outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: side,
        AVVideoHeightKey: side,
        AVVideoCompressionPropertiesKey: [
          AVVideoAverageBitRateKey: max(300_000, side * side * 4),
          AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
        ],
      ]
    )
    writerInput.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: writerInput,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: side,
        kCVPixelBufferHeightKey as String: side,
        kCVPixelBufferIOSurfacePropertiesKey as String: [:],
      ]
    )
    guard writer.canAdd(writerInput) else {
      throw AnimatedAvatarTranscodeError.cannotCreateWriter
    }
    writer.add(writerInput)
    guard reader.startReading(), writer.startWriting() else {
      throw AnimatedAvatarTranscodeError.cannotStartWriter
    }
    writer.startSession(atSourceTime: .zero)

    let ciContext = CIContext(options: [.cacheIntermediates: false])
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    var firstTimestamp: CMTime?
    var wroteFrame = false
    while let sample = readerOutput.copyNextSampleBuffer() {
      guard let sourceBuffer = CMSampleBufferGetImageBuffer(sample) else { continue }
      let sourceTimestamp = CMSampleBufferGetPresentationTimeStamp(sample)
      let start = firstTimestamp ?? sourceTimestamp
      firstTimestamp = start
      let timestamp = CMTimeSubtract(sourceTimestamp, start)
      if timestamp.seconds > maximumDuration { break }
      while !writerInput.isReadyForMoreMediaData {
        if writer.status == .failed || writer.status == .cancelled {
          throw AnimatedAvatarTranscodeError.exportFailed(
            writer.error?.localizedDescription ?? "encoder stopped"
          )
        }
        Thread.sleep(forTimeInterval: 0.002)
      }
      guard
        let pool = adaptor.pixelBufferPool,
        let outputBuffer = allocatePixelBuffer(pool: pool)
      else {
        throw AnimatedAvatarTranscodeError.cannotCreatePixelBuffer
      }

      var image = CIImage(cvPixelBuffer: sourceBuffer)
        .transformed(by: track.preferredTransform)
      let extent = image.extent.standardized
      image = image.transformed(
        by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY)
      )
      let orientedWidth = extent.width
      let orientedHeight = extent.height
      let cropRect = CGRect(
        x: orientedWidth * CGFloat(crop.left),
        y: orientedHeight * CGFloat(1 - crop.top - crop.height),
        width: orientedWidth * CGFloat(crop.width),
        height: orientedHeight * CGFloat(crop.height)
      )
      let cropped = image
        .cropped(to: cropRect)
        .transformed(
          by: CGAffineTransform(
            translationX: -cropRect.minX,
            y: -cropRect.minY
          )
        )
        .transformed(
          by: CGAffineTransform(
            scaleX: CGFloat(side) / cropRect.width,
            y: CGFloat(side) / cropRect.height
          )
        )
      ciContext.render(
        cropped,
        to: outputBuffer,
        bounds: CGRect(x: 0, y: 0, width: side, height: side),
        colorSpace: colorSpace
      )
      guard adaptor.append(outputBuffer, withPresentationTime: timestamp) else {
        throw AnimatedAvatarTranscodeError.cannotAppendFrame
      }
      wroteFrame = true
    }
    guard wroteFrame else {
      throw AnimatedAvatarTranscodeError.missingFrames
    }
    writerInput.markAsFinished()
    reader.cancelReading()
    let semaphore = DispatchSemaphore(value: 0)
    writer.finishWriting { semaphore.signal() }
    semaphore.wait()
    guard writer.status == .completed else {
      throw AnimatedAvatarTranscodeError.exportFailed(
        writer.error?.localizedDescription ?? "unknown encoder error"
      )
    }
    return outputURL.path
  }

  private static func frameDuration(source: CGImageSource, index: Int) -> Double {
    guard
      let raw = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
    else {
      return defaultFrameDuration
    }
    let gif = raw[kCGImagePropertyGIFDictionary] as? [CFString: Any]
    let png = raw[kCGImagePropertyPNGDictionary] as? [CFString: Any]
    let value =
      gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double ??
      gif?[kCGImagePropertyGIFDelayTime] as? Double ??
      png?[kCGImagePropertyAPNGUnclampedDelayTime] as? Double ??
      png?[kCGImagePropertyAPNGDelayTime] as? Double ??
      defaultFrameDuration
    return max(value, minimumFrameDuration)
  }

  private static func makePixelBuffer(
    image: CGImage,
    side: Int,
    crop: AnimatedAvatarCropRegion,
    pool: CVPixelBufferPool
  ) -> CVPixelBuffer? {
    var optionalBuffer: CVPixelBuffer?
    guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &optionalBuffer) == kCVReturnSuccess,
          let pixelBuffer = optionalBuffer
    else {
      return nil
    }
    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
    guard
      let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer),
      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: baseAddress,
        width: side,
        height: side,
        bitsPerComponent: 8,
        bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
        space: colorSpace,
        bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue |
          CGImageAlphaInfo.premultipliedFirst.rawValue
      )
    else {
      return nil
    }
    context.setFillColor(UIColor.black.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: side, height: side))
    let cropWidth = CGFloat(image.width) * CGFloat(crop.width)
    let cropHeight = CGFloat(image.height) * CGFloat(crop.height)
    let scaleX = CGFloat(side) / cropWidth
    let scaleY = CGFloat(side) / cropHeight
    context.interpolationQuality = .high
    context.draw(
      image,
      in: CGRect(
        x: -CGFloat(image.width) * CGFloat(crop.left) * scaleX,
        y: -CGFloat(image.height) * CGFloat(crop.top) * scaleY,
        width: CGFloat(image.width) * scaleX,
        height: CGFloat(image.height) * scaleY
      )
    )
    return pixelBuffer
  }

  private static func allocatePixelBuffer(pool: CVPixelBufferPool) -> CVPixelBuffer? {
    var buffer: CVPixelBuffer?
    guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess else {
      return nil
    }
    return buffer
  }
}

@available(iOS 17.4, *)
@MainActor
private final class LiveCommunicationBridge: NSObject, ConversationManagerDelegate {
  private let channel: FlutterMethodChannel
  private let manager: ConversationManager
  private var localActionIds = Set<UUID>()
  private let audioSessionChanged: (Bool) -> Void

  init(
    messenger: FlutterBinaryMessenger,
    audioSessionChanged: @escaping (Bool) -> Void
  ) {
    channel = FlutterMethodChannel(
      name: "mithka/live_communication",
      binaryMessenger: messenger
    )
    let configuration = ConversationManager.Configuration(
      ringtoneName: nil,
      iconTemplateImageData: nil,
      maximumConversationGroups: 1,
      maximumConversationsPerConversationGroup: 1,
      includesConversationInRecents: true,
      supportsVideo: true,
      supportedHandleTypes: [.generic]
    )
    manager = ConversationManager(configuration: configuration)
    self.audioSessionChanged = audioSessionChanged
    super.init()
    manager.delegate = self
    channel.setMethodCallHandler { [weak self] call, result in
      Task { @MainActor in
        await self?.handle(call: call, result: result)
      }
    }
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) async {
    guard
      let arguments = call.arguments as? [String: Any],
      let uuidString = arguments["uuid"] as? String,
      let uuid = UUID(uuidString: uuidString)
    else {
      result(
        FlutterError(
          code: "live_communication_invalid_arguments",
          message: "A valid conversation UUID is required",
          details: nil
        )
      )
      return
    }

    do {
      switch call.method {
      case "start":
        let title = (arguments["title"] as? String)?.trimmingCharacters(
          in: .whitespacesAndNewlines
        )
        let rawMembers = arguments["members"] as? [String] ?? []
        var handles = rawMembers.filter { !$0.isEmpty }.map {
          Handle(type: .generic, value: $0, displayName: $0)
        }
        if handles.isEmpty {
          let displayName = title?.isEmpty == false ? title! : "Telegram"
          handles = [Handle(type: .generic, value: displayName, displayName: displayName)]
        } else if let title, !title.isEmpty {
          handles[0].displayName = title
        }
        let action = StartConversationAction(
          conversationUUID: uuid,
          handles: handles,
          isVideo: arguments["isVideo"] as? Bool ?? false
        )
        localActionIds.insert(action.uuid)
        try await manager.perform([action])
      case "connected":
        guard let conversation = conversation(uuid: uuid) else {
          result(nil)
          return
        }
        manager.reportConversationEvent(
          .conversationConnected(Date()),
          for: conversation
        )
      case "setMuted":
        let action = MuteConversationAction(
          conversationUUID: uuid,
          isMuted: arguments["muted"] as? Bool ?? false
        )
        localActionIds.insert(action.uuid)
        try await manager.perform([action])
      case "updateMembers":
        guard let conversation = conversation(uuid: uuid) else {
          result(nil)
          return
        }
        let names = arguments["members"] as? [String] ?? []
        let handles = Set(
          names.filter { !$0.isEmpty }.map {
            Handle(type: .generic, value: $0, displayName: $0)
          }
        )
        manager.reportConversationEvent(
          .conversationUpdated(Conversation.Update(members: handles)),
          for: conversation
        )
      case "end":
        let action = EndConversationAction(conversationUUID: uuid)
        localActionIds.insert(action.uuid)
        try await manager.perform([action])
      default:
        result(FlutterMethodNotImplemented)
        return
      }
      result(nil)
    } catch {
      result(
        FlutterError(
          code: "live_communication_failed",
          message: error.localizedDescription,
          details: nil
        )
      )
    }
  }

  private func conversation(uuid: UUID) -> Conversation? {
    manager.conversations.first { $0.uuid == uuid }
  }

  func conversationManager(
    _ manager: ConversationManager,
    conversationChanged conversation: Conversation
  ) {}

  func conversationManagerDidBegin(_ manager: ConversationManager) {}

  func conversationManagerDidReset(_ manager: ConversationManager) {}

  func conversationManager(
    _ manager: ConversationManager,
    perform action: ConversationAction
  ) {
    let wasRequestedByFlutter = localActionIds.remove(action.uuid) != nil
    switch action {
    case let start as StartConversationAction:
      start.fulfill(dateStarted: Date())
    case let join as JoinConversationAction:
      join.fulfill(dateConnected: Date())
    case let mute as MuteConversationAction:
      if !wasRequestedByFlutter {
        channel.invokeMethod(
          "setMuted",
          arguments: [
            "uuid": mute.conversationUUID.uuidString,
            "muted": mute.isMuted
          ]
        )
      }
      mute.fulfill()
    case let end as EndConversationAction:
      if !wasRequestedByFlutter {
        channel.invokeMethod(
          "end",
          arguments: ["uuid": end.conversationUUID.uuidString]
        )
      }
      end.fulfill(dateEnded: Date())
    default:
      action.fulfill()
    }
  }

  func conversationManager(
    _ manager: ConversationManager,
    timedOutPerforming action: ConversationAction
  ) {
    localActionIds.remove(action.uuid)
    action.fail()
  }

  func conversationManager(
    _ manager: ConversationManager,
    didActivate audioSession: AVAudioSession
  ) {
    audioSessionChanged(true)
    channel.invokeMethod("audioSessionActivated", arguments: nil)
  }

  func conversationManager(
    _ manager: ConversationManager,
    didDeactivate audioSession: AVAudioSession
  ) {
    audioSessionChanged(false)
    channel.invokeMethod("audioSessionDeactivated", arguments: nil)
  }
}

@MainActor
private final class SystemPictureInPictureBridge: NSObject, AVPictureInPictureControllerDelegate {
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

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "mithka/system_picture_in_picture",
      binaryMessenger: messenger
    )
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      Task { @MainActor in
        self?.handle(call: call, result: result)
      }
    }
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isSupported":
      let supported = AVPictureInPictureController.isPictureInPictureSupported()
      NSLog("Mithka system PiP isSupported: \(supported)")
      result(supported)
    case "prepare":
      result(prepare(call: call))
    case "startPrepared":
      startPrepared(call: call, result: result)
    case "update":
      update(call: call)
      result(nil)
    case "cancel":
      let args = call.arguments as? [String: Any]
      let id = args?["id"] as? String
      if id == nil || id == activeId {
        stop(notifyFlutter: false)
      }
      result(nil)
    case "start":
      start(call: call, result: result)
    case "stop":
      stop()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func start(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard prepare(call: call) else {
      result(false)
      return
    }
    startPrepared(call: call, result: result)
  }

  private func prepare(call: FlutterMethodCall) -> Bool {
    guard AVPictureInPictureController.isPictureInPictureSupported() else {
      NSLog("Mithka system PiP prepare failed: unsupported")
      return false
    }
    guard
      let args = call.arguments as? [String: Any],
      let id = args["id"] as? String,
      let rawURL = args["url"] as? String,
      let url = URL(string: rawURL)
    else {
      NSLog("Mithka system PiP prepare failed: bad arguments")
      return false
    }

    stop(notifyFlutter: false)

    do {
      let audioSession = AVAudioSession.sharedInstance()
      try audioSession.setCategory(.playback, mode: .moviePlayback)
      try audioSession.setActive(true)
    } catch {
      // PiP can still work when another owner already configured the session.
      NSLog("Mithka system PiP audio session setup failed: \(error.localizedDescription)")
    }

    NSLog("Mithka system PiP prepare source: \(url.absoluteString)")
    let item = AVPlayerItem(url: url)
    let player = AVPlayer(playerItem: item)
    applyPlaybackArguments(args, to: player, shouldSeek: true)

    guard let (layer, pipController, hostView) = attach(player: player) else {
      NSLog("Mithka system PiP prepare failed: could not attach AVPlayerLayer")
      return false
    }

    self.activeId = id
    self.player = player
    self.playerLayer = layer
    self.pictureInPictureController = pipController
    self.hostView = hostView
    return true
  }

  private func startPrepared(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard
      let args = call.arguments as? [String: Any],
      let id = args["id"] as? String,
      id == activeId,
      let player,
      let pipController = pictureInPictureController
    else {
      NSLog("Mithka system PiP startPrepared failed: no active prepared controller")
      result(false)
      return
    }

    applyPlaybackArguments(args, to: player, shouldSeek: true)
    beginPictureInPictureStart(player: player, pipController: pipController, result: result)
  }

  private func update(call: FlutterMethodCall) {
    guard
      let args = call.arguments as? [String: Any],
      let id = args["id"] as? String,
      id == activeId,
      let player
    else {
      return
    }
    applyPlaybackArguments(args, to: player, shouldSeek: true)
  }

  private func applyPlaybackArguments(
    _ args: [String: Any],
    to player: AVPlayer,
    shouldSeek: Bool
  ) {
    player.isMuted = args["muted"] as? Bool ?? false
    preferredRate = (args["speed"] as? NSNumber)?.floatValue ?? 1.0
    if shouldSeek {
      let positionMs = (args["positionMs"] as? NSNumber)?.doubleValue ?? 0
      if positionMs > 0 {
        let currentMs = player.currentTime().seconds * 1000
        if currentMs.isNaN || abs(currentMs - positionMs) > 750 {
          player.seek(
            to: CMTime(seconds: positionMs / 1000.0, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
          )
        }
      }
    }
  }

  private func beginPictureInPictureStart(
    player: AVPlayer,
    pipController: AVPictureInPictureController,
    result: @escaping FlutterResult
  ) {
    startTimeout?.cancel()
    startTimeout = nil
    possibleObservation?.invalidate()
    possibleObservation = nil
    statusObservation?.invalidate()
    statusObservation = nil
    self.pendingStartResult = result

    player.play()
    let speed = preferredRate
    if speed > 0, speed != 1.0 {
      player.rate = speed
    }

    let timeout = DispatchWorkItem { [weak self] in
      guard let self, self.pendingStartResult != nil else { return }
      let itemStatus = player.currentItem?.status.rawValue ?? -1
      let itemError = player.currentItem?.error?.localizedDescription ?? "none"
      NSLog(
        "Mithka system PiP start timed out: possible=\(pipController.isPictureInPicturePossible) itemStatus=\(itemStatus) itemError=\(itemError)"
      )
      self.pendingStartResult?(false)
      self.pendingStartResult = nil
      self.possibleObservation?.invalidate()
      self.possibleObservation = nil
      self.statusObservation?.invalidate()
      self.statusObservation = nil
      self.stop(notifyFlutter: false)
    }
    startTimeout = timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + 6.0, execute: timeout)

    possibleObservation = pipController.observe(
      \.isPictureInPicturePossible,
      options: [.initial, .new]
    ) { [weak self, weak pipController] _, _ in
      Task { @MainActor in
        guard let self, let pipController else { return }
        self.startPictureInPictureIfPossible(pipController)
      }
    }

    statusObservation = player.currentItem?.observe(
      \.status,
      options: [.initial, .new]
    ) { [weak self] item, _ in
      Task { @MainActor in
        if item.status == .failed {
          let error = item.error?.localizedDescription ?? "unknown"
          NSLog("Mithka system PiP item failed: \(error)")
          self?.pendingStartResult?(false)
          self?.pendingStartResult = nil
          self?.stop(notifyFlutter: false)
        }
      }
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self, weak pipController] in
      Task { @MainActor in
        guard
          let self,
          let pipController,
          self.pendingStartResult != nil,
          self.pictureInPictureController === pipController
        else {
          return
        }
        self.possibleObservation?.invalidate()
        self.possibleObservation = nil
        self.statusObservation?.invalidate()
        self.statusObservation = nil
        NSLog(
          "Mithka system PiP force start: possible=\(pipController.isPictureInPicturePossible)"
        )
        if pipController.isPictureInPicturePossible {
          pipController.startPictureInPicture()
        } else {
          self.possibleObservation = pipController.observe(
            \.isPictureInPicturePossible,
            options: [.new]
          ) { [weak self, weak pipController] _, _ in
            Task { @MainActor in
              guard let self, let pipController else { return }
              self.startPictureInPictureIfPossible(pipController)
            }
          }
        }
      }
    }
  }

  private func startPictureInPictureIfPossible(_ pipController: AVPictureInPictureController) {
    guard
      pendingStartResult != nil,
      pictureInPictureController === pipController,
      pipController.isPictureInPicturePossible
    else {
      return
    }
    possibleObservation?.invalidate()
    possibleObservation = nil
    statusObservation?.invalidate()
    statusObservation = nil
    NSLog("Mithka system PiP startPictureInPicture")
    pipController.startPictureInPicture()
  }

  private func attach(player: AVPlayer) -> (AVPlayerLayer, AVPictureInPictureController, UIView)? {
    guard let root = Self.rootViewController() else { return nil }
    let hostView = UIView(frame: root.view.bounds)
    hostView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    hostView.alpha = 0.01
    hostView.backgroundColor = .clear
    hostView.isUserInteractionEnabled = false
    let layer = AVPlayerLayer(player: player)
    layer.frame = hostView.bounds
    layer.videoGravity = .resizeAspect
    hostView.layer.addSublayer(layer)
    root.view.addSubview(hostView)

    guard let pipController = AVPictureInPictureController(playerLayer: layer) else {
      hostView.removeFromSuperview()
      return nil
    }
    pipController.delegate = self
    if #available(iOS 14.2, *) {
      pipController.canStartPictureInPictureAutomaticallyFromInline = true
    }
    return (layer, pipController, hostView)
  }

  private func stop(notifyFlutter: Bool = true) {
    startTimeout?.cancel()
    startTimeout = nil
    possibleObservation?.invalidate()
    possibleObservation = nil
    statusObservation?.invalidate()
    statusObservation = nil
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
    preferredRate = 1.0

    if notifyFlutter, let stoppedId {
      channel.invokeMethod("didStop", arguments: ["id": stoppedId])
    }
  }

  nonisolated func pictureInPictureControllerDidStartPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    Task { @MainActor in
      startTimeout?.cancel()
      startTimeout = nil
      pendingStartResult?(true)
      pendingStartResult = nil
    }
  }

  nonisolated func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    failedToStartPictureInPictureWithError error: Error
  ) {
    Task { @MainActor in
      pendingStartResult?(false)
      pendingStartResult = nil
      stop(notifyFlutter: false)
    }
  }

  nonisolated func pictureInPictureControllerDidStopPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    Task { @MainActor in
      stop()
    }
  }

  nonisolated func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler:
      @escaping (Bool) -> Void
  ) {
    completionHandler(false)
  }

  private static func rootViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let activeScene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    let root = activeScene?.windows.first { $0.isKeyWindow }?.rootViewController
    return topViewController(from: root)
  }

  private static func topViewController(from root: UIViewController?) -> UIViewController? {
    if let nav = root as? UINavigationController {
      return topViewController(from: nav.visibleViewController)
    }
    if let tab = root as? UITabBarController {
      return topViewController(from: tab.selectedViewController)
    }
    if let presented = root?.presentedViewController {
      return topViewController(from: presented)
    }
    return root
  }
}

private final class AccountSessionBackupKeychain {
  private let service: String

  init() {
    let bundleId = Bundle.main.bundleIdentifier ?? "ad.neko.mithka"
    self.service = "\(bundleId).sessionsbackup"
  }

  func handle(call: FlutterMethodCall, result: FlutterResult) {
    do {
      switch call.method {
      case "isSupported":
        result(true)
      case "saveSession":
        guard
          let args = call.arguments as? [String: Any],
          let id = args["id"] as? String,
          !id.isEmpty,
          let data = args["data"] as? FlutterStandardTypedData
        else {
          throw AccountSessionBackupError.invalidArguments
        }
        try saveSession(id: id, data: data.data)
        result(nil)
      case "getAllSessions":
        result(try getAllSessions().map { FlutterStandardTypedData(bytes: $0) })
      case "deleteSession":
        guard
          let args = call.arguments as? [String: Any],
          let id = args["id"] as? String,
          !id.isEmpty
        else {
          throw AccountSessionBackupError.invalidArguments
        }
        try deleteSession(id: id)
        result(nil)
      case "deleteAllSessions":
        try deleteAllSessions()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    } catch {
      result(
        FlutterError(
          code: "account_backup_failed",
          message: error.localizedDescription,
          details: nil
        )
      )
    }
  }

  private func saveSession(id: String, data: Data) throws {
    do {
      try saveSession(id: id, data: data, synchronizable: true)
    } catch AccountSessionBackupError.keychain(let status)
      where isSynchronizableUnsupported(status) {
      try saveSession(id: id, data: data, synchronizable: false)
    }
  }

  private func saveSession(id: String, data: Data, synchronizable: Bool) throws {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: id,
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
    ]
    if synchronizable {
      query[kSecAttrSynchronizable as String] = true
    }

    let status = SecItemAdd(query as CFDictionary, nil)
    if status == errSecDuplicateItem {
      var updateQuery: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: id
      ]
      if synchronizable {
        updateQuery[kSecAttrSynchronizable as String] = true
      }
      let updateStatus = SecItemUpdate(
        updateQuery as CFDictionary,
        [
          kSecValueData as String: data,
          kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ] as CFDictionary
      )
      guard updateStatus == errSecSuccess else {
        throw AccountSessionBackupError.keychain(updateStatus)
      }
    } else if status != errSecSuccess {
      throw AccountSessionBackupError.keychain(status)
    }
  }

  private func getAllSessions() throws -> [Data] {
    do {
      return try getAllSessions(synchronizable: kSecAttrSynchronizableAny)
    } catch AccountSessionBackupError.keychain(let status)
      where isSynchronizableUnsupported(status) {
      return try getAllSessions(synchronizable: nil)
    }
  }

  private func getAllSessions(synchronizable: CFString?) throws -> [Data] {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitAll
    ]
    if let synchronizable {
      query[kSecAttrSynchronizable as String] = synchronizable
    }
    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound {
      return []
    }
    guard status == errSecSuccess else {
      throw AccountSessionBackupError.keychain(status)
    }
    return result as? [Data] ?? []
  }

  private func deleteSession(id: String) throws {
    do {
      try deleteSession(id: id, synchronizable: kSecAttrSynchronizableAny)
    } catch AccountSessionBackupError.keychain(let status)
      where isSynchronizableUnsupported(status) {
      try deleteSession(id: id, synchronizable: nil)
    }
  }

  private func deleteSession(id: String, synchronizable: CFString?) throws {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: id
    ]
    if let synchronizable {
      query[kSecAttrSynchronizable as String] = synchronizable
    }
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw AccountSessionBackupError.keychain(status)
    }
  }

  private func deleteAllSessions() throws {
    do {
      try deleteAllSessions(synchronizable: kSecAttrSynchronizableAny)
    } catch AccountSessionBackupError.keychain(let status)
      where isSynchronizableUnsupported(status) {
      try deleteAllSessions(synchronizable: nil)
    }
  }

  private func deleteAllSessions(synchronizable: CFString?) throws {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service
    ]
    if let synchronizable {
      query[kSecAttrSynchronizable as String] = synchronizable
    }
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw AccountSessionBackupError.keychain(status)
    }
  }

  private func isSynchronizableUnsupported(_ status: OSStatus) -> Bool {
    status == errSecNotAvailable || status == errSecMissingEntitlement || status == errSecParam
  }
}

private enum AccountSessionBackupError: LocalizedError {
  case invalidArguments
  case keychain(OSStatus)

  var errorDescription: String? {
    switch self {
    case .invalidArguments:
      return "Invalid account backup arguments"
    case let .keychain(status):
      return "Keychain error \(status)"
    }
  }
}

@available(iOS 18.0, *)
@MainActor
private final class NativeTranslationBridge {
  private let coordinator = NativeTranslationCoordinator()
  private var hostController: UIHostingController<NativeTranslationHostView>?

  func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "translate" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard
      let args = call.arguments as? [String: Any],
      let text = args["text"] as? String,
      let targetLanguageCode = args["targetLanguageCode"] as? String,
      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !targetLanguageCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      result(
        FlutterError(
          code: "invalid_arguments",
          message: "缺少翻译文本或目标语言",
          details: nil
        )
      )
      return
    }

    attachHostIfNeeded()
    guard hostController != nil else {
      result(
        FlutterError(
          code: "translator_unavailable",
          message: "本机翻译暂不可用",
          details: nil
        )
      )
      return
    }

    coordinator.enqueue(
      text: text,
      sourceLanguageCode: args["sourceLanguageCode"] as? String,
      targetLanguageCode: targetLanguageCode,
      result: result
    )
  }

  func attachHostIfNeeded() {
    guard hostController == nil else { return }
    guard let root = Self.rootViewController() else { return }
    let host = UIHostingController(
      rootView: NativeTranslationHostView(coordinator: coordinator)
    )
    host.view.isHidden = true
    host.view.backgroundColor = .clear
    host.view.isUserInteractionEnabled = false
    root.addChild(host)
    root.view.addSubview(host.view)
    host.view.frame = .zero
    host.didMove(toParent: root)
    hostController = host
  }

  private static func rootViewController() -> UIViewController? {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first { $0.isKeyWindow }?
      .rootViewController
  }
}

@available(iOS 18.0, *)
private struct NativeTranslationHostView: View {
  @ObservedObject var coordinator: NativeTranslationCoordinator

  var body: some View {
    Color.clear
      .frame(width: 0, height: 0)
      .translationTask(coordinator.configuration) { session in
        await coordinator.perform(session: session)
      }
  }
}

@available(iOS 18.0, *)
@MainActor
private final class NativeTranslationCoordinator: ObservableObject {
  @Published var configuration: TranslationSession.Configuration?

  private var queue: [NativeTranslationRequest] = []
  private var activeRequestId: UUID?
  private var configurationSourceKey: String?
  private var configurationTargetKey: String?
  private var timeoutTask: Task<Void, Never>?

  func enqueue(
    text: String,
    sourceLanguageCode: String?,
    targetLanguageCode: String,
    result: @escaping FlutterResult
  ) {
    queue.append(
      NativeTranslationRequest(
        text: text,
        sourceLanguageCode: sourceLanguageCode,
        targetLanguageCode: targetLanguageCode,
        result: result
      )
    )
    startNextIfNeeded()
  }

  func perform(session: TranslationSession) async {
    guard
      let activeRequestId,
      let request = queue.first(where: { $0.id == activeRequestId })
    else { return }

    do {
      let response = try await session.translate(request.text)
      guard self.activeRequestId == activeRequestId else { return }
      request.result(response.targetText)
    } catch {
      guard self.activeRequestId == activeRequestId else { return }
      request.result(
        FlutterError(
          code: "translation_failed",
          message: error.localizedDescription,
          details: nil
        )
      )
    }

    finishActiveRequest(activeRequestId)
  }

  private func startNextIfNeeded() {
    guard activeRequestId == nil, let request = queue.first else { return }
    let sourceKey = Self.normalizedLanguageKey(for: request.sourceLanguageCode)
    guard
      let targetKey = Self.normalizedLanguageKey(for: request.targetLanguageCode),
      let target = Self.localeLanguage(for: targetKey)
    else {
      request.result(
        FlutterError(
          code: "unsupported_language",
          message: "不支持目标语言 \(request.targetLanguageCode)",
          details: nil
        )
      )
      queue.removeFirst()
      startNextIfNeeded()
      return
    }

    activeRequestId = request.id
    startTimeout(for: request.id)

    if configuration == nil ||
      configurationSourceKey != sourceKey ||
      configurationTargetKey != targetKey
    {
      configuration = TranslationSession.Configuration(
        source: Self.localeLanguage(for: sourceKey),
        target: target
      )
      configurationSourceKey = sourceKey
      configurationTargetKey = targetKey
    } else {
      configuration?.invalidate()
    }
  }

  private func startTimeout(for requestId: UUID) {
    timeoutTask?.cancel()
    timeoutTask = Task { @MainActor in
      try? await Task.sleep(nanoseconds: 55_000_000_000)
      guard self.activeRequestId == requestId,
        let request = self.queue.first(where: { $0.id == requestId })
      else { return }
      request.result(
        FlutterError(
          code: "translation_timeout",
          message: "本机翻译已取消或超时",
          details: nil
        )
      )
      self.finishActiveRequest(requestId)
    }
  }

  private func finishActiveRequest(_ requestId: UUID) {
    timeoutTask?.cancel()
    timeoutTask = nil
    queue.removeAll { $0.id == requestId }
    if activeRequestId == requestId {
      activeRequestId = nil
    }
    if !queue.isEmpty {
      Task { @MainActor in
        self.startNextIfNeeded()
      }
    }
  }

  private static func localeLanguage(for code: String?) -> Locale.Language? {
    guard let normalized = normalizedLanguageKey(for: code) else { return nil }
    return Locale.Language(identifier: normalized)
  }

  private static func normalizedLanguageKey(for code: String?) -> String? {
    guard
      let code,
      !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return nil }
    let normalized = code
      .replacingOccurrences(of: "_", with: "-")
      .lowercased()
    if normalized == "auto" || normalized == "autodetect" {
      return nil
    }
    if normalized == "zh" || normalized == "zh-hans" || normalized == "zh-cn" {
      return "zh-Hans"
    }
    if normalized == "zh-hant" || normalized == "zh-tw" || normalized == "zh-hk" {
      return "zh-Hant"
    }
    return normalized.components(separatedBy: "-").first ?? normalized
  }
}

private struct NativeTranslationRequest {
  let id = UUID()
  let text: String
  let sourceLanguageCode: String?
  let targetLanguageCode: String
  let result: FlutterResult
}
