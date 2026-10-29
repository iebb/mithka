import Flutter
import Intents
import UIKit
import AVFoundation
import UserNotifications
import XCTest
@testable import Runner

/// Hosted in the app bundle, so `@testable` sees the Runner target's internal
/// symbols (AppDelegate.centredSquareCrop and friends).
final class RunnerTests: XCTestCase {

  func testHandoffPayloadContainsOnlyNavigationIdentity() throws {
    let payload = try XCTUnwrap(
      HandoffPayload(
        arguments: [
          "version": 1,
          "activityId": "handoff-test",
          "accountUserId": 42,
          "chatId": -100_123,
          "messageId": 88,
        ]
      )
    )

    XCTAssertEqual(payload.accountUserID, 42)
    XCTAssertEqual(payload.chatID, -100_123)
    XCTAssertEqual(payload.messageID, 88)
    XCTAssertNil(payload.dictionary["sessionString"])
  }

  func testHandoffPayloadRejectsZeroAndFutureValues() {
    XCTAssertNil(
      HandoffPayload(
        arguments: [
          "version": 2,
          "activityId": "future",
          "accountUserId": 42,
          "chatId": 7,
        ]
      )
    )
    XCTAssertNil(
      HandoffPayload(
        arguments: [
          "version": 1,
          "activityId": "invalid",
          "accountUserId": 42,
          "chatId": 0,
        ]
      )
    )
    XCTAssertNil(
      HandoffPayload(
        arguments: [
          "version": 1,
          "activityId": "temporary-message",
          "accountUserId": 42,
          "chatId": 7,
          "messageId": -1,
        ]
      )
    )
  }

  @available(iOS 15.0, *)
  func testCommunicationNotificationUsesChatAvatarAndTapPayload() throws {
    let iconURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("mithka-notification-chat-icon.png")
    let png = try XCTUnwrap(
      Data(
        base64Encoded:
          "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
      )
    )
    try png.write(to: iconURL, options: .atomic)
    defer { try? FileManager.default.removeItem(at: iconURL) }

    let request = try XCTUnwrap(
      CommunicationNotificationRequest(
        arguments: [
          "id": 42,
          "title": "Family",
          "body": "Dinner is ready",
          "conversation_identifier": "2:-100123",
          "sender_name": "Alice",
          "payload": "{\"chat_id\":-100123,\"message_id\":8}",
          "group_conversation": true,
          "play_sound": false,
          "chat_id": -100123,
          "chat_icon_path": iconURL.path,
        ]
      )
    )

    XCTAssertEqual(request.identifier, "mithka.communication.42")
    let content = request.baseContent()
    XCTAssertEqual(content.threadIdentifier, "2:-100123")
    XCTAssertNil(content.sound)
    XCTAssertEqual(
      content.userInfo["payload"] as? String,
      "{\"chat_id\":-100123,\"message_id\":8}"
    )

    let intent = request.messageIntent()
    XCTAssertEqual(intent.sender?.displayName, "Alice")
    XCTAssertNil(intent.sender?.image)
    XCTAssertEqual(intent.conversationIdentifier, "2:-100123")
    XCTAssertEqual(intent.speakableGroupName?.spokenPhrase, "Family")
    XCTAssertNotNil(intent.image(forParameterNamed: \.speakableGroupName))

    let updated = try content.updating(from: intent)
    XCTAssertEqual(updated.body, "Dinner is ready")
  }

  @available(iOS 15.0, *)
  func testPrivateCommunicationNotificationPinsAvatarToSenderParameter() throws {
    let iconURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("mithka-private-notification-icon.png")
    let png = try XCTUnwrap(
      Data(
        base64Encoded:
          "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
      )
    )
    try png.write(to: iconURL, options: .atomic)
    defer { try? FileManager.default.removeItem(at: iconURL) }
    let request = try XCTUnwrap(
      CommunicationNotificationRequest(
        arguments: [
          "id": 43,
          "title": "Alice",
          "body": "Hello",
          "conversation_identifier": "0:99",
          "sender_name": "Alice",
          "payload": "{\"chat_id\":99}",
          "group_conversation": false,
          "play_sound": true,
          "chat_id": 99,
          "chat_icon_path": iconURL.path,
        ]
      )
    )

    let intent = request.messageIntent()

    XCTAssertNotNil(intent.sender?.image)
    XCTAssertNotNil(intent.image(forParameterNamed: \.sender))
  }

  @available(iOS 15.0, *)
  func testRemoteTelegramPushMapsToGroupCommunicationIntent() throws {
    let content = UNMutableNotificationContent()
    content.title = "Family"
    content.body = "Dinner is ready"
    let remote = try XCTUnwrap(
      RemoteCommunicationNotification(
        content: content,
        userInfo: [
          "data": [
            "user_id": "7001",
            "loc_key": "CHAT_MESSAGE_TEXT",
            "loc_args": ["Alice", "Family", "Dinner is ready"],
            "custom": [
              "channel_id": "123",
              "chat_from_id": "42",
              "msg_id": "8",
            ],
          ],
        ]
      )
    )

    XCTAssertEqual(remote.chatId, -1_000_000_000_123)
    XCTAssertEqual(remote.information.title, "Family")
    XCTAssertEqual(remote.information.senderName, "Alice")
    XCTAssertEqual(remote.information.body, "Dinner is ready")
    XCTAssertEqual(
      remote.information.conversationIdentifier,
      "telegram:7001:-1000000000123"
    )
    XCTAssertTrue(remote.information.groupConversation)
    XCTAssertEqual(
      remote.information.messageIntent().speakableGroupName?.spokenPhrase,
      "Family"
    )
  }

  @MainActor
  func testNativeGlassSelectionHierarchyCapsulesRTLAndResize() throws {
    let host = GlassSurfaceHost(frame: CGRect(x: 0, y: 0, width: 300, height: 72))
    var config: [String: Any] = [
      "radius": 999, "selection": 0, "itemCount": 4, "selectionInset": 5,
      "durationMs": 0, "dark": false, "tint": UInt32(0x5CFFFFFF),
      "selectionTint": UInt32(0x1A007AFF), "rtl": false,
    ]
    host.apply(config)
    let outer = try XCTUnwrap(host.subviews.first as? UIVisualEffectView)
    let selected = try XCTUnwrap(outer.contentView.subviews.first as? UIVisualEffectView)
    XCTAssertEqual(host.subviews.count, 1)
    XCTAssertFalse(host.isUserInteractionEnabled)
    XCTAssertTrue(host.accessibilityElementsHidden)
    XCTAssertEqual(outer.frame, host.bounds)
    XCTAssertEqual(outer.layer.cornerRadius, 36)
    XCTAssertEqual(selected.frame, CGRect(x: 5, y: 5, width: 72.5, height: 62))
    XCTAssertEqual(selected.layer.cornerRadius, 31)

    for count in 1...4 {
      for rtl in [false, true] {
        for selection in 0..<count {
          config["itemCount"] = count
          config["selection"] = selection
          config["rtl"] = rtl
          host.apply(config)
          let width = CGFloat(290) / CGFloat(count)
          let slot = rtl ? count - 1 - selection : selection
          // UIView stores center + bounds, so fractional third-slot origins can
          // round by ~1e-14 when frame is reconstructed. Keep subpixel accuracy
          // without requiring bit-identical floating-point arithmetic.
          XCTAssertEqual(selected.frame.minX, 5 + CGFloat(slot) * width, accuracy: 0.000001)
          XCTAssertEqual(selected.frame.minY, 5, accuracy: 0.000001)
          XCTAssertEqual(selected.frame.width, width, accuracy: 0.000001)
          XCTAssertEqual(selected.frame.height, 62, accuracy: 0.000001)
          XCTAssertEqual(selected.layer.cornerRadius, min(width, 62) / 2)
        }
      }
    }
    config["itemCount"] = 4
    config["selection"] = 1
    config["rtl"] = true
    host.apply(config)
    host.frame.size = CGSize(width: 180, height: 100)
    host.setNeedsLayout()
    host.layoutIfNeeded()
    XCTAssertEqual(outer.frame, host.bounds)
    XCTAssertEqual(outer.layer.cornerRadius, 50)
    XCTAssertEqual(selected.frame, CGRect(x: 90, y: 5, width: 42.5, height: 90))
    XCTAssertEqual(selected.layer.cornerRadius, 21.25)
    config["selection"] = -1
    host.apply(config)
    XCTAssertTrue(selected.isHidden)
  }

  @MainActor
  func testNativeGlassOpaqueFallbackAndFreshTintAssignment() throws {
    let host = GlassSurfaceHost(frame: CGRect(x: 0, y: 0, width: 300, height: 72))
    var config: [String: Any] = [
      "radius": 999, "selection": 1, "itemCount": 3, "selectionInset": 5,
      "durationMs": 0, "dark": false, "highContrast": true,
      "opaqueBackground": UInt32(0xFFEEEEEE), "opaqueSelection": UInt32(0xFFCCDDFF),
      "contrastBorder": UInt32(0xFF007AFF),
    ]
    host.apply(config)
    let outer = try XCTUnwrap(host.subviews.first as? UIVisualEffectView)
    let selected = try XCTUnwrap(outer.contentView.subviews.first as? UIVisualEffectView)
    XCTAssertNil(outer.effect)
    XCTAssertNil(selected.effect)
    XCTAssertEqual(outer.backgroundColor?.cgColor.alpha, 1)
    XCTAssertEqual(selected.backgroundColor?.cgColor.alpha, 1)
    XCTAssertEqual(selected.layer.borderWidth, 1)
    XCTAssertEqual(selected.layer.cornerRadius, 31)

    config["highContrast"] = false
    config["tint"] = UInt32(0x5CFFFFFF)
    config["selectionTint"] = UInt32(0x30007AFF)
    host.apply(config)
    if !UIAccessibility.isReduceTransparencyEnabled && !UIAccessibility.isDarkerSystemColorsEnabled {
      if #available(iOS 26.0, *) {
        let firstOuter = try XCTUnwrap(outer.effect as? UIGlassEffect)
        let firstSelected = try XCTUnwrap(selected.effect as? UIGlassEffect)
        config["dark"] = true
        config["tint"] = UInt32(0x20101010)
        config["selectionTint"] = UInt32(0x4000FF00)
        host.apply(config)
        let nextOuter = try XCTUnwrap(outer.effect as? UIGlassEffect)
        let nextSelected = try XCTUnwrap(selected.effect as? UIGlassEffect)
        XCTAssertFalse(firstOuter === nextOuter)
        XCTAssertFalse(firstSelected === nextSelected)
        XCTAssertNotEqual(firstSelected.tintColor, nextSelected.tintColor)
        XCTAssertEqual(outer.overrideUserInterfaceStyle, .dark)
        XCTAssertEqual(selected.overrideUserInterfaceStyle, .dark)
      } else {
        XCTAssertTrue(outer.effect is UIBlurEffect)
        XCTAssertTrue(selected.effect is UIBlurEffect)
        XCTAssertNotNil(selected.contentView.backgroundColor)
      }
    }
  }

  @MainActor
  func testNativeGlassRapidRetargetThenResizeAndReducedDurationSettleLatestSlot() throws {
    let host = GlassSurfaceHost(frame: CGRect(x: 0, y: 0, width: 300, height: 72))
    var config: [String: Any] = [
      "radius": 999, "selection": 0, "itemCount": 4, "selectionInset": 5,
      "durationMs": 280, "dark": false,
    ]
    host.apply(config)
    for selection in [3, 1, 2] {
      config["selection"] = selection
      host.apply(config)
    }
    let outer = try XCTUnwrap(host.subviews.first as? UIVisualEffectView)
    let selected = try XCTUnwrap(outer.contentView.subviews.first as? UIVisualEffectView)
    host.frame.size.width = 220
    host.setNeedsLayout()
    host.layoutIfNeeded()
    XCTAssertEqual(selected.frame, CGRect(x: 110, y: 5, width: 52.5, height: 62))
    config["selection"] = 0
    host.apply(config)
    config["selection"] = 3
    config["durationMs"] = 0
    host.apply(config)
    XCTAssertEqual(selected.frame, CGRect(x: 162.5, y: 5, width: 52.5, height: 62))
    XCTAssertEqual(selected.layer.cornerRadius, 26.25)
    // Endpoint/layout coverage only; live interruption continuity and material
    // contrast still require on-device/simulator optical verification.
  }
}



// MARK: - Video note crop maths

/// Orientation/crop maths behind `cropVideoNote`, plus the real export the app
/// runs. `AppDelegate` is `@MainActor`, but both members under test are
/// `nonisolated` pure/async functions, so these tests stay plain synchronous
/// XCTest cases or plain `async` tests: no main-actor hop, no expectations.
final class VideoNoteCropTests: XCTestCase {
  private let tolerance: CGFloat = 0.001

  private func assertCentredSquare(
    natural: CGSize,
    transform: CGAffineTransform,
    expectedSide: CGFloat,
    expectedOrigin: CGPoint,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let crop = AppDelegate.centredSquareCrop(naturalSize: natural, transform: transform)
    XCTAssertEqual(crop.side, expectedSide, accuracy: tolerance, file: file, line: line)
    XCTAssertEqual(crop.rect.width, crop.rect.height, accuracy: tolerance, file: file, line: line)
    XCTAssertEqual(crop.rect.origin.x, expectedOrigin.x, accuracy: tolerance, file: file, line: line)
    XCTAssertEqual(crop.rect.origin.y, expectedOrigin.y, accuracy: tolerance, file: file, line: line)
  }

  /// The transform a camera writes for a given sensor orientation. `natural` is
  /// the encoded frame; display is `naturalSize.applying(preferredTransform)`.
  private func transform(for degrees: Int, natural: CGSize) -> CGAffineTransform {
    switch degrees {
    case 0:
      return .identity
    case 90:
      // Natural (w,h) displayed as (h,w), turned portrait.
      return CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: natural.height, ty: 0)
    case 180:
      return CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: natural.width, ty: natural.height)
    case 270:
      return CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: natural.width)
    default:
      XCTFail("unsupported rotation \(degrees)")
      return .identity
    }
  }

  func testLandscapeRecordingCropsTheCentredSquare() {
    // 1280x720 displayed as 1280x720, square 720 at x=280.
    assertCentredSquare(
      natural: CGSize(width: 1280, height: 720),
      transform: .identity,
      expectedSide: 720,
      expectedOrigin: CGPoint(x: 280, y: 0)
    )
  }

  func testPortraitRecordingUsesTheDisplayedFrame() {
    // 1280x720 encoded, 720x1280 displayed: square 720 at the display origin.
    assertCentredSquare(
      natural: CGSize(width: 1280, height: 720),
      transform: transform(for: 90, natural: CGSize(width: 1280, height: 720)),
      expectedSide: 720,
      expectedOrigin: CGPoint(x: 0, y: 280)
    )
  }

  func testUpsideDownRecordingKeepsTheSquareInsideTheFrame() {
    let natural = CGSize(width: 1280, height: 720)
    let transform = self.transform(for: 180, natural: natural)
    let crop = AppDelegate.centredSquareCrop(naturalSize: natural, transform: transform)
    XCTAssertEqual(crop.side, 720, accuracy: tolerance)
    // A 180-degree rotation moves the frame's origin to (1280, 720); the
    // centred square must still start one margin in, never outside the frame.
    XCTAssertEqual(crop.rect.minX, 280, accuracy: tolerance)
    XCTAssertEqual(crop.rect.minY, 0, accuracy: tolerance)
  }

  func testQuarterTurnTheOtherWayIsMirroredCorrectly() {
    // 1280x720 encoded, 720x1280 displayed: square 720 at y=280.
    // (270 degrees has the same displayed bounds as 90 but the opposite
    // handedness, so the crop maths must not be special-cased to one of them.)
    assertCentredSquare(
      natural: CGSize(width: 1280, height: 720),
      transform: transform(for: 270, natural: CGSize(width: 1280, height: 720)),
      expectedSide: 720,
      expectedOrigin: CGPoint(x: 0, y: 280)
    )
  }

  func testSquareInputNeedsNoCrop() {
    assertCentredSquare(
      natural: CGSize(width: 720, height: 720),
      transform: .identity,
      expectedSide: 720,
      expectedOrigin: .zero
    )
  }

  func testOddDimensionsRoundDownToAnEvenSquare() {
    // 1081x721 -> square 720, even, one pixel inside the one-pixel squareness
    // tolerance the output check and the Dart side accept.
    assertCentredSquare(
      natural: CGSize(width: 1081, height: 721),
      transform: .identity,
      expectedSide: 720,
      expectedOrigin: CGPoint(x: 180.5, y: 0.5)
    )
  }

  func testTinyRecordingNeverProducesADegenerateSquare() {
    let crop = AppDelegate.centredSquareCrop(
      naturalSize: CGSize(width: 2, height: 1),
      transform: .identity
    )
    XCTAssertGreaterThanOrEqual(crop.side, 2)
    XCTAssertEqual(crop.rect.width, crop.rect.height, accuracy: tolerance)
  }

  /// The layer transform must move the chosen square's corner to the origin of
  /// the square render size; a regression here shifts a rotated recording out
  /// of the render (the reason setCropRectangle is not used).
  ///
  /// The frame is fed to the layer in its NATURAL orientation
  /// (`CGRect(origin: .zero, size: naturalSize)`), so the square whose corners
  /// are checked has to be pulled back out of display space through the
  /// recording's rotation first. Applying the layer to the natural frame
  /// instead checks the whole - uncropped - frame, whose edge starts `side/2`
  /// pixels outside the render whenever the recording is rotated; that is the
  /// crop working, not a regression.
  private func naturalSquare(
    of crop: AppDelegate.VideoNoteCropRegion,
    natural: CGSize,
    transform: CGAffineTransform
  ) -> CGRect {
    let corners = [
      CGPoint(x: crop.rect.minX, y: crop.rect.minY),
      CGPoint(x: crop.rect.maxX, y: crop.rect.minY),
      CGPoint(x: crop.rect.maxX, y: crop.rect.maxY),
      CGPoint(x: crop.rect.minX, y: crop.rect.maxY),
    ].map { $0.applying(transform.inverted()) }
    let xs = corners.map(\.x)
    let ys = corners.map(\.y)
    let rect = CGRect(
      x: xs.min() ?? 0,
      y: ys.min() ?? 0,
      width: (xs.max() ?? 0) - (xs.min() ?? 0),
      height: (ys.max() ?? 0) - (ys.min() ?? 0)
    )
    XCTAssertTrue(
      CGRect(origin: .zero, size: natural).insetBy(dx: -tolerance, dy: -tolerance).contains(rect),
      "the square \(rect) must lie inside the natural frame"
    )
    return rect
  }

  func testLayerTransformMapsTheSquareCornerToTheOrigin() {
    let natural = CGSize(width: 1280, height: 720)
    let transform = self.transform(for: 90, natural: natural)
    let crop = AppDelegate.centredSquareCrop(naturalSize: natural, transform: transform)
    let layer = transform.concatenating(
      CGAffineTransform(translationX: -crop.rect.origin.x, y: -crop.rect.origin.y)
    )
    let source = naturalSquare(of: crop, natural: natural, transform: transform)
    // Corners, not `CGRect.applying`: the rotation makes the corner order
    // important, and `applying` on a rect normalises it as if it were a
    // translated origin-anchored rect.
    let corners = [
      CGPoint(x: source.minX, y: source.minY),
      CGPoint(x: source.maxX, y: source.minY),
      CGPoint(x: source.maxX, y: source.maxY),
      CGPoint(x: source.minX, y: source.maxY),
    ].map { $0.applying(layer) }
    XCTAssertEqual(corners.map(\.x).min() ?? -1, 0, accuracy: tolerance)
    XCTAssertEqual(corners.map(\.y).min() ?? -1, 0, accuracy: tolerance)
    XCTAssertEqual((corners.map(\.x).max() ?? 0) - (corners.map(\.x).min() ?? 0), crop.side, accuracy: tolerance)
    XCTAssertEqual((corners.map(\.y).max() ?? 0) - (corners.map(\.y).min() ?? 0), crop.side, accuracy: tolerance)
  }

  /// The same boundary for every rotation the recorder can produce, not only
  /// the quarter turn.
  func testLayerTransformMapsTheSquareForEveryRotation() {
    let natural = CGSize(width: 1280, height: 720)
    for degrees in [0, 90, 180, 270] {
      let transform = self.transform(for: degrees, natural: natural)
      let crop = AppDelegate.centredSquareCrop(naturalSize: natural, transform: transform)
      let layer = transform.concatenating(
        CGAffineTransform(translationX: -crop.rect.origin.x, y: -crop.rect.origin.y)
      )
      let source = naturalSquare(of: crop, natural: natural, transform: transform)
      let corners = [
        CGPoint(x: source.minX, y: source.minY),
        CGPoint(x: source.maxX, y: source.minY),
        CGPoint(x: source.maxX, y: source.maxY),
        CGPoint(x: source.minX, y: source.maxY),
      ].map { $0.applying(layer) }
      let xs = corners.map(\.x)
      let ys = corners.map(\.y)
      XCTAssertEqual(xs.min() ?? -1, 0, accuracy: tolerance, "\(degrees) degrees: x origin")
      XCTAssertEqual(ys.min() ?? -1, 0, accuracy: tolerance, "\(degrees) degrees: y origin")
      XCTAssertEqual((xs.max() ?? 0) - (xs.min() ?? 0), crop.side, accuracy: tolerance, "\(degrees) degrees: width")
      XCTAssertEqual((ys.max() ?? 0) - (ys.min() ?? 0), crop.side, accuracy: tolerance, "\(degrees) degrees: height")
    }
  }

  // MARK: - Real AVAssetExportSession exports

  /// One synthetic recording: a solid-colour video track and, when `withAudio`
  /// is set, a silent audio track, written with AVAssetWriter exactly like a
  /// camera file (encoded frame plus a `preferredTransform` for the rotation).
  private struct SyntheticMovie {
    let url: URL
    let duration: Double
    let naturalSize: CGSize
    let degrees: Int
  }

  private func makeSyntheticMovie(
    named name: String,
    naturalSize: CGSize,
    degrees: Int,
    duration: Double = 1.0,
    withAudio: Bool
  ) throws -> SyntheticMovie {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("mithka-input-\(name)-\(UUID().uuidString)")
      .appendingPathExtension("mov")
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let fps = 30
    let frameCount = max(2, Int(duration * Double(fps)))

    let videoInput = AVAssetWriterInput(
      mediaType: .video,
      outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: Int(naturalSize.width),
        AVVideoHeightKey: Int(naturalSize.height),
      ]
    )
    videoInput.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: videoInput,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: Int(naturalSize.width),
        kCVPixelBufferHeightKey as String: Int(naturalSize.height),
      ]
    )
    guard writer.canAdd(videoInput) else {
      throw XCTSkip("AVAssetWriter cannot encode H.264 video in this runtime")
    }
    writer.add(videoInput)

    var audioInput: AVAssetWriterInput?
    if withAudio {
      let input = AVAssetWriterInput(
        mediaType: .audio,
        outputSettings: [
          AVFormatIDKey: kAudioFormatMPEG4AAC,
          AVSampleRateKey: 44_100,
          AVNumberOfChannelsKey: 1,
          AVEncoderBitRateKey: 64_000,
        ]
      )
      input.expectsMediaDataInRealTime = false
      guard writer.canAdd(input) else {
        throw XCTSkip("AVAssetWriter cannot encode AAC audio in this runtime")
      }
      writer.add(input)
      audioInput = input
    }

    guard writer.startWriting() else {
      throw XCTSkip("AVAssetWriter refused to start: \(String(describing: writer.error))")
    }
    writer.startSession(atSourceTime: .zero)

    // Solid-colour frames at 30 fps.
    for frame in 0..<frameCount {
      while !videoInput.isReadyForMoreMediaData {
        Thread.sleep(forTimeInterval: 0.001)
      }
      guard let pool = adaptor.pixelBufferPool else {
        throw XCTSkip("No pixel buffer pool for the synthetic movie")
      }
      var pixelBuffer: CVPixelBuffer?
      _ = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
      guard let buffer = pixelBuffer else {
        throw XCTSkip("Could not allocate a pixel buffer")
      }
      CVPixelBufferLockBaseAddress(buffer, [])
      if let base = CVPixelBufferGetBaseAddress(buffer) {
        memset(base, 0x40, CVPixelBufferGetDataSize(buffer))
      }
      CVPixelBufferUnlockBaseAddress(buffer, [])
      let time = CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps))
      guard adaptor.append(buffer, withPresentationTime: time) else {
        throw XCTSkip("AVAssetWriter rejected a video frame: \(String(describing: writer.error))")
      }
    }
    videoInput.markAsFinished()

    if let audioInput {
      // Silent PCM, converted to the AAC settings above by the writer.
      let sampleRate = 44_100.0
      let framesPerBuffer = 1_024
      let bufferCount = max(1, Int((duration * sampleRate) / Double(framesPerBuffer)))
      for index in 0..<bufferCount {
        while !audioInput.isReadyForMoreMediaData {
          Thread.sleep(forTimeInterval: 0.001)
        }
        let sampleBuffer = try makeSilentAudioSampleBuffer(
          frames: framesPerBuffer,
          sampleRate: sampleRate,
          presentationTime: CMTime(
            value: CMTimeValue(index * framesPerBuffer),
            timescale: CMTimeScale(sampleRate)
          )
        )
        guard audioInput.append(sampleBuffer) else {
          throw XCTSkip("AVAssetWriter rejected an audio buffer: \(String(describing: writer.error))")
        }
      }
      audioInput.markAsFinished()
    }

    // A semaphore, not an XCTestExpectation: the export tests are async and run
    // off the main thread, where waiting on an expectation would need a run
    // loop this helper does not own.
    let finished = DispatchSemaphore(value: 0)
    writer.finishWriting { finished.signal() }
    guard finished.wait(timeout: .now() + 60) == .success else {
      throw XCTSkip("AVAssetWriter did not finish within 60s")
    }
    guard writer.status == .completed else {
      throw XCTSkip("AVAssetWriter failed: \(String(describing: writer.error))")
    }
    // Carry the rotation the camera would have written.
    try applyPreferredTransform(
      transform(for: degrees, natural: naturalSize),
      to: url
    )
    return SyntheticMovie(
      url: url,
      duration: duration,
      naturalSize: naturalSize,
      degrees: degrees
    )
  }

  private func makeSilentAudioSampleBuffer(
    frames: Int,
    sampleRate: Double,
    presentationTime: CMTime
  ) throws -> CMSampleBuffer {
    var asbd = AudioStreamBasicDescription(
      mSampleRate: sampleRate,
      mFormatID: kAudioFormatLinearPCM,
      mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
      mBytesPerPacket: 2,
      mFramesPerPacket: 1,
      mBytesPerFrame: 2,
      mChannelsPerFrame: 1,
      mBitsPerChannel: 16,
      mReserved: 0
    )
    var format: CMAudioFormatDescription?
    let formatStatus = CMAudioFormatDescriptionCreate(
      allocator: kCFAllocatorDefault,
      asbd: &asbd,
      layoutSize: 0,
      layout: nil,
      magicCookieSize: 0,
      magicCookie: nil,
      extensions: nil,
      formatDescriptionOut: &format
    )
    guard formatStatus == noErr, let format else {
      throw XCTSkip("Could not describe the silent audio format: \(formatStatus)")
    }
    // 16-bit mono zero samples: a block buffer the writer can convert to AAC.
    let byteCount = frames * 2
    var blockBuffer: CMBlockBuffer?
    let blockStatus = CMBlockBufferCreateWithMemoryBlock(
      allocator: kCFAllocatorDefault,
      memoryBlock: nil,
      blockLength: byteCount,
      blockAllocator: kCFAllocatorDefault,
      customBlockSource: nil,
      offsetToData: 0,
      dataLength: byteCount,
      flags: kCMBlockBufferAssureMemoryNowFlag,
      blockBufferOut: &blockBuffer
    )
    guard blockStatus == noErr, let blockBuffer else {
      throw XCTSkip("Could not allocate silence: \(blockStatus)")
    }
    _ = CMBlockBufferFillDataBytes(
      with: 0,
      blockBuffer: blockBuffer,
      offsetIntoDestination: 0,
      dataLength: byteCount
    )
    var sampleBuffer: CMSampleBuffer?
    let status = CMAudioSampleBufferCreateWithPacketDescriptions(
      allocator: kCFAllocatorDefault,
      dataBuffer: blockBuffer,
      dataReady: true,
      makeDataReadyCallback: nil,
      refcon: nil,
      formatDescription: format,
      sampleCount: CMItemCount(frames),
      presentationTimeStamp: presentationTime,
      packetDescriptions: nil,
      sampleBufferOut: &sampleBuffer
    )
    guard status == noErr, let sampleBuffer else {
      throw XCTSkip("Could not create an audio sample buffer: \(status)")
    }
    return sampleBuffer
  }

  /// Writes `preferredTransform` onto an existing movie the way the camera
  /// does: the same encoded frames re-muxed with the rotation matrix the
  /// exporter reads. A passthrough export of a composition carries the
  /// composition track's transform into the output file.
  private func applyPreferredTransform(
    _ transform: CGAffineTransform,
    to url: URL
  ) throws {
    let asset = AVURLAsset(url: url)
    guard let sourceVideo = asset.tracks(withMediaType: .video).first else {
      throw XCTSkip("Synthetic movie has no video track to rotate")
    }
    let composition = AVMutableComposition()
    let range = CMTimeRange(start: .zero, duration: asset.duration)
    guard
      let videoTrack = composition.addMutableTrack(
        withMediaType: .video,
        preferredTrackID: kCMPersistentTrackID_Invalid
      )
    else {
      throw XCTSkip("Could not build the rotation composition")
    }
    try videoTrack.insertTimeRange(range, of: sourceVideo, at: .zero)
    videoTrack.preferredTransform = transform
    if let sourceAudio = asset.tracks(withMediaType: .audio).first,
      let audioTrack = composition.addMutableTrack(
        withMediaType: .audio,
        preferredTrackID: kCMPersistentTrackID_Invalid
      )
    {
      try audioTrack.insertTimeRange(range, of: sourceAudio, at: .zero)
    }
    guard
      let export = AVAssetExportSession(
        asset: composition,
        presetName: AVAssetExportPresetPassthrough
      )
    else {
      throw XCTSkip("Passthrough export is unavailable on this runtime")
    }
    let rotated = url.deletingPathExtension()
      .appendingPathExtension("rotated.mov")
    try? FileManager.default.removeItem(at: rotated)
    export.outputURL = rotated
    export.outputFileType = .mov
    let finished = DispatchSemaphore(value: 0)
    export.exportAsynchronously {
      finished.signal()
    }
    guard finished.wait(timeout: .now() + 60) == .success else {
      throw XCTSkip("Rotation pass-through did not finish within 60s")
    }
    guard export.status == .completed else {
      throw XCTSkip("Rotation pass-through failed: \(String(describing: export.error))")
    }
    try? FileManager.default.removeItem(at: url)
    try FileManager.default.moveItem(at: rotated, to: url)
  }

  private func assertExportedSquare(
    _ movie: SyntheticMovie,
    file: StaticString = #filePath,
    line: UInt = #line
  ) async throws {
    guard
      AVAssetExportSession(
        asset: AVURLAsset(url: movie.url),
        presetName: AVAssetExportPresetHighestQuality
      ) != nil
    else {
      throw XCTSkip("AVAssetExportSession is unavailable in this runtime")
    }
    let output = FileManager.default.temporaryDirectory
      .appendingPathComponent("mithka-test-export-\(UUID().uuidString)")
      .appendingPathExtension("mp4")
    defer { try? FileManager.default.removeItem(at: output) }

    let result = try await AppDelegate.exportCentredSquareVideoNote(
      input: movie.url,
      output: output
    )
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: output.path),
      "the export must leave a file behind",
      file: file,
      line: line
    )
    let exported = AVURLAsset(url: output)
    let track = try XCTUnwrap(
      exported.tracks(withMediaType: .video).first,
      "the export must carry a video track",
      file: file,
      line: line
    )
    let natural = track.naturalSize
    // Corners, not `CGRect.applying`: a 180-degree transform is
    // (-1, 0, 0, -1, w, h), whose determinant is +1, so a rect spanning the
    // encoded frame comes back out ordered rather than mirrored and a square
    // check on that form is vacuous. Four corners are correct for every
    // rotation and mirror.
    let displayed = [
      CGPoint(x: 0, y: 0),
      CGPoint(x: natural.width, y: 0),
      CGPoint(x: natural.width, y: natural.height),
      CGPoint(x: 0, y: natural.height),
    ].map { $0.applying(track.preferredTransform) }
    let displayedWidth = (displayed.map(\.x).max() ?? 0) - (displayed.map(\.x).min() ?? 0)
    let displayedHeight = (displayed.map(\.y).max() ?? 0) - (displayed.map(\.y).min() ?? 0)
    XCTAssertTrue(
      abs(natural.width - natural.height) <= 1,
      "natural size \(natural) is not square",
      file: file,
      line: line
    )
    XCTAssertTrue(
      abs(displayedWidth - displayedHeight) <= 1,
      "displayed size \(displayedWidth)x\(displayedHeight) is not square",
      file: file,
      line: line
    )
    XCTAssertEqual(
      result.side,
      max(2, min(displayedWidth, displayedHeight)),
      accuracy: 1,
      file: file,
      line: line
    )
    let duration = CMTimeGetSeconds(exported.duration)
    XCTAssertEqual(
      duration,
      movie.duration,
      accuracy: 0.25,
      "export duration \(duration)s drifted from the input \(movie.duration)s",
      file: file,
      line: line
    )
    XCTAssertEqual(result.duration, duration, accuracy: 0.05, file: file, line: line)
    let audio = exported.tracks(withMediaType: .audio)
    XCTAssertEqual(
      audio.count,
      1,
      "the export dropped the recording's audio track",
      file: file,
      line: line
    )
    if let audioTrack = audio.first {
      XCTAssertGreaterThan(
        CMTimeGetSeconds(audioTrack.timeRange.duration),
        movie.duration - 0.3,
        "the exported audio is shorter than the recording",
        file: file,
        line: line
      )
    }
  }

  func testExportedLandscapeNoteIsSquareWithAudio() async throws {
    let movie = try makeSyntheticMovie(
      named: "landscape",
      naturalSize: CGSize(width: 640, height: 360),
      degrees: 0,
      withAudio: true
    )
    defer { try? FileManager.default.removeItem(at: movie.url) }
    try await assertExportedSquare(movie)
  }

  func testExportedPortraitNoteIsSquareWithAudio() async throws {
    let movie = try makeSyntheticMovie(
      named: "portrait",
      naturalSize: CGSize(width: 640, height: 360),
      degrees: 90,
      withAudio: true
    )
    defer { try? FileManager.default.removeItem(at: movie.url) }
    try await assertExportedSquare(movie)
  }

  func testExportedUpsideDownNoteIsSquareWithAudio() async throws {
    let movie = try makeSyntheticMovie(
      named: "upside-down",
      naturalSize: CGSize(width: 640, height: 360),
      degrees: 180,
      withAudio: true
    )
    defer { try? FileManager.default.removeItem(at: movie.url) }
    try await assertExportedSquare(movie)
  }

  func testExportedQuarterTurnNoteIsSquareWithAudio() async throws {
    let movie = try makeSyntheticMovie(
      named: "quarter-turn",
      naturalSize: CGSize(width: 640, height: 360),
      degrees: 270,
      withAudio: true
    )
    defer { try? FileManager.default.removeItem(at: movie.url) }
    try await assertExportedSquare(movie)
  }

  /// The audio-free path a device without a microphone track hits: the export
  /// must not invent or require audio.
  func testExportedSilentNoteIsStillSquare() async throws {
    let movie = try makeSyntheticMovie(
      named: "silent",
      naturalSize: CGSize(width: 640, height: 360),
      degrees: 90,
      withAudio: false
    )
    defer { try? FileManager.default.removeItem(at: movie.url) }
    guard
      AVAssetExportSession(
        asset: AVURLAsset(url: movie.url),
        presetName: AVAssetExportPresetHighestQuality
      ) != nil
    else {
      throw XCTSkip("AVAssetExportSession is unavailable in this runtime")
    }
    let output = FileManager.default.temporaryDirectory
      .appendingPathComponent("mithka-test-export-\(UUID().uuidString)")
      .appendingPathExtension("mp4")
    defer { try? FileManager.default.removeItem(at: output) }
    let result = try await AppDelegate.exportCentredSquareVideoNote(
      input: movie.url,
      output: output
    )
    XCTAssertEqual(result.side, 360, accuracy: 1)
    let exported = AVURLAsset(url: output)
    let track = try XCTUnwrap(exported.tracks(withMediaType: .video).first)
    XCTAssertTrue(
      abs(track.naturalSize.width - track.naturalSize.height) <= 1,
      "natural size \(track.naturalSize) is not square"
    )
  }

  /// A missing input is a clean failure that leaves no output file behind.
  func testExportOfAMissingRecordingFailsWithoutLeavingAFile() async {
    let missing = FileManager.default.temporaryDirectory
      .appendingPathComponent("mithka-missing-\(UUID().uuidString).mov")
    let output = FileManager.default.temporaryDirectory
      .appendingPathComponent("mithka-missing-out-\(UUID().uuidString).mp4")
    do {
      _ = try await AppDelegate.exportCentredSquareVideoNote(
        input: missing,
        output: output
      )
      XCTFail("exporting a missing recording must throw")
    } catch {
      XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }
  }
}

/// Actual production UIKit host tests. Gesture/compositing and the native
/// public-control hit-map still require parent-owned simulator acceptance.
class NativeTabBarTests: XCTestCase {
  /// Match the production Flutter root's bar policy without starting another
  /// Flutter engine for each synthetic UIKit fixture.
  @MainActor
  private class HorizontalBarRoot: UIViewController {
    @available(iOS 27.1, *)
    override var preferredVerticalBarBehavior: UIVerticalBarBehavior { .disabled }
  }

  @MainActor
  func testApplicationRootUsesTheHorizontalEmbeddedBarPolicy() throws {
    let root = try XCTUnwrap(UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .compactMap { $0.rootViewController as? MithkaFlutterViewController }.first,
      "The application storyboard must install the owned Flutter root")
    if #available(iOS 27.1, *) {
      XCTAssertEqual(root.preferredVerticalBarBehavior, .disabled)
    }
  }
  @MainActor
  private func configuration() throws -> [String: Any] {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let png = try XCTUnwrap(UIGraphicsImageRenderer(
      size: CGSize(width: 25, height: 25), format: format
    ).image {
      UIColor.white.setFill()
      $0.fill(CGRect(x: 3, y: 3, width: 19, height: 19))
    }.pngData())
    let image = FlutterStandardTypedData(bytes: png)
    return [
      "selectedId": 0, "dark": false, "rtl": false, "actionEpoch": 1,
      "markAllReadLabel": "Mark all as read", "readActionImage": image, "imageScale": 1.0,
      "tint": NSNumber(value: UInt32(0xFF007AFF)), "bottomInset": 0.0,
      "items": [
        ["id": 0, "label": "Messages", "unread": 123456, "canMarkAllRead": true,
         "image": image, "selectedImage": image, "imageScale": 1.0],
        ["id": 2, "label": "Contacts", "unread": 0, "canMarkAllRead": false,
         "image": image, "selectedImage": image, "imageScale": 1.0],
      ],
    ]
  }

  @MainActor
  func testActualControllerContainmentTemplateImagesLabelsAndFullBadges() throws {
    let parent = HorizontalBarRoot()
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    window.rootViewController = parent
    window.makeKeyAndVisible()
    defer { window.isHidden = true }
    let host = NativeTabBarHost(frame: CGRect(x: 0, y: 700, width: 390, height: 1))
    parent.view.addSubview(host)
    host.apply(try configuration())
    host.layoutIfNeeded()
    XCTAssertTrue(host.controller is UITabBarController)
    XCTAssertTrue(host.tabBar is UITabBar)
    XCTAssertTrue(host.controller.parent === parent)
    XCTAssertTrue(host.controller.view.superview === host)
    XCTAssertTrue(host.controller.delegate === host)
    XCTAssertTrue(host.tabBar.isUserInteractionEnabled)
    let items = try XCTUnwrap(host.tabBar.items)
    XCTAssertEqual(items.map(\.tag), [0, 2])
    XCTAssertEqual(items.map(\.title), ["Messages", "Contacts"])
    XCTAssertEqual(items[0].accessibilityLabel, "Messages")
    XCTAssertEqual(items[0].accessibilityIdentifier, "bottom-tab-0")
    XCTAssertEqual(items[0].badgeValue, "123456")
    XCTAssertEqual(items[0].accessibilityValue, "123456")
    XCTAssertNil(items[1].badgeValue)
    XCTAssertEqual(items[0].image?.renderingMode, .alwaysTemplate)
    XCTAssertEqual(items[0].selectedImage?.renderingMode, .alwaysTemplate)
    XCTAssertEqual(items[0].image?.size, CGSize(width: 25, height: 25))
    XCTAssertEqual(host.controller.selectedViewController?.tabBarItem.tag, 0)
    host.detachController()
    XCTAssertNil(host.controller.parent)
  }

  @MainActor
  func testDelegateForwardsSelectionAndReselectionOnlyForEnabledControllers() throws {
    let host = NativeTabBarHost(frame: .zero)
    host.apply(try configuration())
    let children = try XCTUnwrap(host.controller.viewControllers)
    var selections: [Int] = []
    host.onSelect = { selections.append($0) }
    host.controller.delegate?.tabBarController?(host.controller, didSelect: children[1])
    host.controller.delegate?.tabBarController?(host.controller, didSelect: children[1])
    host.controller.delegate?.tabBarController?(host.controller, didSelect: UIViewController())
    XCTAssertEqual(selections, [2, 2])
  }

  @MainActor
  func testLiveBadgeLabelThemeRTLAndEnabledItemsReuseNativeItems() throws {
    let host = NativeTabBarHost(frame: .zero)
    var config = try configuration()
    host.apply(config)
    let first = try XCTUnwrap(host.tabBar.items?.first)
    config["dark"] = true
    config["rtl"] = true
    config["selectedId"] = 2
    var definitions = try XCTUnwrap(config["items"] as? [[String: Any]])
    definitions[0]["unread"] = 7
    definitions[0]["label"] = "الرسائل"
    config["items"] = definitions
    host.apply(config)
    XCTAssertTrue(host.tabBar.items?.first === first)
    XCTAssertEqual(first.badgeValue, "7")
    XCTAssertEqual(first.accessibilityValue, "7")
    XCTAssertEqual(first.title, "الرسائل")
    XCTAssertEqual(first.accessibilityLabel, "الرسائل")
    XCTAssertEqual(host.controller.overrideUserInterfaceStyle, .dark)
    XCTAssertEqual(host.tabBar.semanticContentAttribute, .forceRightToLeft)
    XCTAssertEqual(host.controller.selectedViewController?.tabBarItem.tag, 2)
    definitions[0]["unread"] = 0
    config["items"] = [definitions[0]]
    config["selectedId"] = 0
    config["dark"] = false
    config["rtl"] = false
    host.apply(config)
    XCTAssertEqual(host.tabBar.items?.map(\.tag), [0])
    XCTAssertNil(first.badgeValue)
    XCTAssertEqual(host.controller.overrideUserInterfaceStyle, .light)
    XCTAssertEqual(host.tabBar.semanticContentAttribute, .forceLeftToRight)
  }

  @MainActor
  func testNaturalMeasurementProvenanceAndCompactSplitInsetContract() throws {
    let host = NativeTabBarHost(frame: CGRect(x: 0, y: 0, width: 390, height: 1))
    var config = try configuration()
    var snapshots: [[String: Any]] = []
    host.onMetrics = { snapshots.append($0) }
    host.apply(config)
    host.layoutIfNeeded()
    let metrics = try XCTUnwrap(snapshots.last)
    let height = try XCTUnwrap(metrics["height"] as? Double)
    XCTAssertGreaterThan(height, 0)
    XCTAssertEqual(CGFloat(height), host.naturalHeight(for: 390))
    XCTAssertNotEqual(CGFloat(height), host.bounds.height)
    XCTAssertEqual(metrics["controllerClass"] as? String, "UITabBarController")
    XCTAssertEqual(metrics["controlClass"] as? String, "UITabBar")
    config["bottomInset"] = 34.0
    host.apply(config)
    host.layoutIfNeeded()
    XCTAssertEqual(host.safeAreaInsets.bottom, 34)
    config["bottomInset"] = 0.0
    host.frame.size = CGSize(width: 280, height: 999)
    host.apply(config)
    host.layoutIfNeeded()
    XCTAssertEqual(host.safeAreaInsets.bottom, 0)
    let count = snapshots.count
    host.apply(config)
    host.layoutIfNeeded()
    XCTAssertEqual(snapshots.count, count + 1)
  }

  @MainActor
  func testReadRequestIsExplicitOnceWorksWithHiddenBadgeAndInvalidatesStaleScope() throws {
    let host = NativeTabBarHost(frame: .zero)
    var config = try configuration()
    var definitions = try XCTUnwrap(config["items"] as? [[String: Any]])
    definitions[0]["unread"] = 0 // visual zero is not actual unread eligibility
    config["items"] = definitions
    config["selectedId"] = 2
    host.apply(config)
    var reads: [Int] = []
    host.onMarkAllRead = { id, _ in reads.append(id) }
    let canceled = host.readRequest(for: 0)
    _ = canceled // creating/opening/canceling never marks or switches
    XCTAssertTrue(reads.isEmpty)
    XCTAssertEqual(host.controller.selectedViewController?.tabBarItem.tag, 2)
    let explicit = host.readRequest(for: 0)
    explicit.perform()
    explicit.perform()
    XCTAssertEqual(reads, [0])
    XCTAssertEqual(host.controller.selectedViewController?.tabBarItem.tag, 2)
    let stale = host.readRequest(for: 0)
    config["actionEpoch"] = 2 // account/route/tab lifetime changed
    host.apply(config)
    stale.perform()
    host.readRequest(for: 2).perform() // Contacts has no existing handler
    XCTAssertEqual(reads, [0])
    XCTAssertEqual(host.tabBar.items?.first?.accessibilityCustomActions?.first?.name, "Mark all as read")
    XCTAssertNil(host.tabBar.items?.last?.accessibilityCustomActions)
  }

  /// Diagnostic only: inspect the public view/accessibility graph of synthetic
  /// Messages/Contacts test tabs. Type names are observations, never selectors.
  @MainActor
  private func publicTabHierarchy(_ host: NativeTabBarHost, rtl: Bool) -> String {
    var lines = ["NATIVE_TAB_PUBLIC_TREE rtl=\(rtl) metrics=\(host.runtimeMetrics())"]
    for item in host.tabBar.items ?? [] {
      lines.append("ITEM tag=\(item.tag) title=\(String(reflecting: item.title)) " +
        "identifier=\(String(reflecting: item.accessibilityIdentifier)) " +
        "label=\(String(reflecting: item.accessibilityLabel)) " +
        "a11yFrame=\(item.accessibilityFrame)")
    }
    var visited = Set<ObjectIdentifier>()
    var remaining = 220
    func visit(_ object: NSObject, path: String, depth: Int) {
      guard depth <= 12, remaining > 0, visited.insert(ObjectIdentifier(object)).inserted else {
        return
      }
      remaining -= 1
      let identifier = (object as? UIAccessibilityIdentification)?.accessibilityIdentifier
      var line = "\(path) type=\(String(describing: type(of: object))) " +
        "identifier=\(String(reflecting: identifier)) " +
        "label=\(String(reflecting: object.accessibilityLabel)) " +
        "value=\(String(reflecting: object.accessibilityValue)) " +
        "isElement=\(object.isAccessibilityElement) traits=\(object.accessibilityTraits.rawValue) " +
        "a11yFrame=\(object.accessibilityFrame)"
      if let view = object as? UIView {
        if let label = view as? UILabel {
          line += " isUILabel=true text=\(String(reflecting: label.text)) " +
            "attributedText=\(String(reflecting: label.attributedText?.string))"
        } else {
          line += " isUILabel=false"
        }
        if let imageView = view as? UIImageView {
          let image = imageView.image
          func comparison(_ candidate: UIImage?) -> String {
            guard let image, let candidate else { return "missing" }
            let sameCGImage: Bool
            if let actualCGImage = image.cgImage, let candidateCGImage = candidate.cgImage {
              sameCGImage = actualCGImage === candidateCGImage
            } else {
              sameCGImage = false
            }
            return "sameUIImage=\(image === candidate),sameCGImage=\(sameCGImage)," +
              "equalUIImage=\(image.isEqual(candidate))"
          }
          let comparisons = (host.tabBar.items ?? []).map { item in
            "tag=\(item.tag):normal{\(comparison(item.image))}," +
              "selected{\(comparison(item.selectedImage))}"
          }
          line += " isUIImageView=true imageSize=\(String(describing: image?.size)) " +
            "imageComparisons=[\(comparisons.joined(separator: ";"))]"
        }
        let center = view.convert(CGPoint(x: view.bounds.midX, y: view.bounds.midY), to: host.tabBar)
        let hit = host.tabBar.hitTest(center, with: nil)
        var hitAncestors: [String] = []
        var current = hit
        while let node = current, hitAncestors.count < 12 {
          hitAncestors.append("\(String(describing: type(of: node)))" +
            "[id=\(String(reflecting: node.accessibilityIdentifier))," +
            "label=\(String(reflecting: node.accessibilityLabel))," +
            "control=\(node is UIControl),frame=\(node.convert(node.bounds, to: host.tabBar))]")
          if node === host { break }
          current = node.superview
        }
        line += " bounds=\(view.bounds) frameInBar=\(view.convert(view.bounds, to: host.tabBar)) " +
          "hidden=\(view.isHidden) alpha=\(view.alpha) interactive=\(view.isUserInteractionEnabled) " +
          "isControl=\(view is UIControl) centerHitAncestors=\(hitAncestors.joined(separator: " -> "))"
      }
      let count = object.accessibilityElementCount()
      line += " a11yCount=\(count)"
      lines.append(line)
      if let elements = object.accessibilityElements {
        for (index, element) in elements.prefix(40).enumerated() {
          if let child = element as? NSObject {
            visit(child, path: "\(path).a11y[\(index)]", depth: depth + 1)
          }
        }
      } else if count != NSNotFound, count > 0, count < 1000 {
        for index in 0..<min(count, 40) {
          if let child = object.accessibilityElement(at: index) as? NSObject {
            visit(child, path: "\(path).a11y[\(index)]", depth: depth + 1)
          }
        }
      }
      if let view = object as? UIView {
        for (index, child) in view.subviews.enumerated() {
          visit(child, path: "\(path).view[\(index)]", depth: depth + 1)
        }
      }
    }
    visit(host, path: "host", depth: 0)
    lines.append("END_NATIVE_TAB_PUBLIC_TREE remaining=\(remaining)")
    return lines.joined(separator: "\n")
  }

  @MainActor
  private final class VisibleTabRoot: HorizontalBarRoot {
    private(set) var appearanceCount = 0
    private(set) var appearanceGeneration = 0
    private(set) var isAppeared = false
    private(set) var appearedAt: CFTimeInterval = 0
    private(set) var disappearedAt: CFTimeInterval = 0
    var onDisappearance: (() -> Void)?
    override func viewDidAppear(_ animated: Bool) {
      super.viewDidAppear(animated)
      appearanceCount += 1
      appearanceGeneration += 1
      isAppeared = true
      appearedAt = CACurrentMediaTime()
    }
    override func viewWillDisappear(_ animated: Bool) {
      super.viewWillDisappear(animated)
      appearanceGeneration += 1
      isAppeared = false
      disappearedAt = CACurrentMediaTime()
      onDisappearance?()
    }
    override func viewDidDisappear(_ animated: Bool) {
      super.viewDidDisappear(animated)
      appearanceGeneration += 1
      isAppeared = false
      disappearedAt = CACurrentMediaTime()
      onDisappearance?()
    }
  }

  @MainActor
  private final class DisplayFrameObserver: NSObject {
    var onFrame: ((CADisplayLink) -> Void)?
    @objc func frame(_ link: CADisplayLink) { onFrame?(link) }
  }

  /// Scene-backed fixture ONLY for real-window diagnosis/acceptance, not faults.
  @MainActor
  private final class VisibleTabWindow: NSObject {
    let scene: UIWindowScene
    let window: UIWindow
    let root = VisibleTabRoot()
    let host: NativeTabBarHost
    private weak var originalKeyWindow: UIWindow?
    var activeMenu: (UIContextMenuInteraction, UIContextMenuConfiguration)?
    private(set) var frameTimestamps: [CFTimeInterval] = []
    private(set) var finalLayoutAt: CFTimeInterval = 0
    private var trackingVisibility = false
    private var visibilityGeneration = 0
    private var readinessLoss: String?
    private var witnessedAppearanceGeneration: Int?
    private var witnessedVisibilityGeneration: Int?

    private static func id(_ object: AnyObject?) -> String {
      object.map { String(describing: ObjectIdentifier($0)) } ?? "nil"
    }

    static func inventory() -> String {
      let app = UIApplication.shared
      let scenes = app.connectedScenes.sorted {
        $0.session.persistentIdentifier < $1.session.persistentIdentifier
      }.map { scene -> String in
        let windows = (scene as? UIWindowScene)?.windows.map { window in
          "id=\(Self.id(window)),a11yID=\(String(reflecting: window.accessibilityIdentifier))," +
          "sceneMatches=\(window.windowScene === scene),hidden=\(window.isHidden)," +
          "alpha=\(window.alpha),key=\(window.isKeyWindow),level=\(window.windowLevel.rawValue)," +
          "frame=\(window.frame),root=\(Self.id(window.rootViewController))"
        }.joined(separator: ";") ?? "not-window-scene"
        return "sceneID=\(scene.session.persistentIdentifier),activation=\(scene.activationState.rawValue)," +
          "windows=[\(windows)]"
      }.joined(separator: " | ")
      return "appState=\(app.applicationState.rawValue) connectedScenes=[\(scenes)]"
    }

    private static func activeScene() -> UIWindowScene? {
      let app = UIApplication.shared
      guard app.applicationState == .active else { return nil }
      return app.connectedScenes.compactMap { $0 as? UIWindowScene }
        .filter { $0.activationState == .foregroundActive && $0.screen === UIScreen.main }
        .sorted { lhs, rhs in
          let leftKey = lhs.windows.contains { $0.isKeyWindow && !$0.isHidden && $0.alpha > 0 }
          let rightKey = rhs.windows.contains { $0.isKeyWindow && !$0.isHidden && $0.alpha > 0 }
          if leftKey != rightKey { return leftKey }
          return lhs.session.persistentIdentifier < rhs.session.persistentIdentifier
        }.first
    }

    static func make() async throws -> VisibleTabWindow {
      if let scene = Self.activeScene() { return VisibleTabWindow(scene: scene) }
      let observer = DisplayFrameObserver()
      let link = CADisplayLink(target: observer, selector: #selector(DisplayFrameObserver.frame(_:)))
      defer { link.invalidate(); observer.onFrame = nil }
      let selected = await withCheckedContinuation { (continuation: CheckedContinuation<UIWindowScene?, Never>) in
        var finished = false
        let deadline = DispatchWorkItem {
          guard !finished else { return }
          finished = true
          continuation.resume(returning: nil)
        }
        observer.onFrame = { _ in
          guard !finished, let scene = Self.activeScene() else { return }
          finished = true
          deadline.cancel()
          continuation.resume(returning: scene)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: deadline)
        link.add(to: .main, forMode: .common)
      }
      let scene = try XCTUnwrap(selected,
        "NATIVE_VISIBLE_WINDOW timeout=8s missing active app/connected foregroundActive scene: \(Self.inventory())")
      return VisibleTabWindow(scene: scene)
    }

    private init(scene: UIWindowScene) {
      self.scene = scene
      originalKeyWindow = scene.windows.first { $0.isKeyWindow }
      window = UIWindow(windowScene: scene)
      host = NativeTabBarHost(frame: CGRect(x: 0, y: 0,
                                           width: scene.coordinateSpace.bounds.width, height: 1))
      super.init()
      window.frame = scene.coordinateSpace.bounds
      window.windowLevel = .normal
      window.alpha = 1
      window.accessibilityIdentifier = "NativeVisibleTabFixture"
      window.rootViewController = root
      root.view.addSubview(host)
      root.onDisappearance = { [weak self] in self?.loseReadiness("root-disappearance") }
      let center = NotificationCenter.default
      for name in [UIApplication.willResignActiveNotification, UIApplication.didEnterBackgroundNotification] {
        center.addObserver(self, selector: #selector(readinessLost(_:)), name: name, object: nil)
      }
      for name in [UIScene.willDeactivateNotification, UIScene.didDisconnectNotification] {
        center.addObserver(self, selector: #selector(readinessLost(_:)), name: name, object: scene)
      }
      for name in [UIWindow.didResignKeyNotification, UIWindow.didBecomeHiddenNotification] {
        center.addObserver(self, selector: #selector(readinessLost(_:)), name: name, object: window)
      }
      // Caller registers unconditional cleanup BEFORE making this window visible.
    }

    private func loseReadiness(_ reason: String) {
      guard trackingVisibility else { return }
      visibilityGeneration += 1
      if readinessLoss == nil { readinessLoss = reason }
    }

    @objc private func readinessLost(_ notification: Notification) {
      loseReadiness(notification.name.rawValue)
    }

    func cleanup() {
      trackingVisibility = false
      NotificationCenter.default.removeObserver(self)
      root.onDisappearance = nil
      host.menuHierarchyDrawing = { bar, rect, updates in
        bar.drawHierarchy(in: rect, afterScreenUpdates: updates)
      }
      if let (interaction, menu) = activeMenu {
        host.contextMenuInteraction(interaction, willEndFor: menu, animator: nil)
      }
      activeMenu = nil
      host.detachController()
      host.removeFromSuperview()
      window.isHidden = true
      window.rootViewController = nil
      if let original = originalKeyWindow, let originalScene = original.windowScene,
        UIApplication.shared.connectedScenes.contains(where: { $0 === originalScene }),
        originalScene.windows.contains(where: { $0 === original }), !original.isHidden {
        original.makeKey()
      }
    }

    private func mappedControl(in view: UIView) -> UIControl? {
      if let control = view as? UIControl, host.itemID(for: control) == 0,
        host.isLiveControl(control) { return control }
      for child in view.subviews {
        if let control = mappedControl(in: child) { return control }
      }
      return nil
    }

    private func lineage(_ view: UIView?) -> [UIView] {
      var result: [UIView] = []
      var node = view
      while let current = node {
        result.append(current)
        node = current.superview
      }
      return result
    }

    func makeKeyAndVisible() {
      trackingVisibility = true
      window.makeKeyAndVisible()
    }

    // Independent of the frame count: checked on EVERY frame callback.
    private func visibleState(control: UIControl? = nil) -> Bool {
      guard trackingVisibility, readinessLoss == nil,
        UIApplication.shared.applicationState == .active,
        UIApplication.shared.connectedScenes.contains(where: { $0 === scene }),
        scene.activationState == .foregroundActive, scene.screen === UIScreen.main,
        window.screen === scene.screen, window.windowScene === scene,
        scene.windows.contains(where: { $0 === window }), !window.isHidden,
        window.alpha == 1, window.windowLevel == .normal, window.isKeyWindow,
        window.rootViewController === root, root.parent == nil,
        root.view.window === window,
        host.controller.parent === root, host.window === window, host.tabBar.window === window
      else { return false }
      let source: UIView = control ?? host.tabBar
      let ancestors = lineage(source)
      let rect = source.convert(source.bounds, to: window)
      guard ancestors.contains(where: { $0 === window }),
        ancestors.allSatisfy({ !$0.isHidden && $0.alpha > 0 }),
        ancestors.reduce(CGFloat(1), { $0 * $1.alpha }) > 0.01,
        !rect.isEmpty, rect.intersects(window.bounds),
        window.bounds.contains(CGPoint(x: rect.midX, y: rect.midY)) else { return false }
      if let control {
        let center = control.convert(CGPoint(x: control.bounds.midX, y: control.bounds.midY), to: window)
        return host.itemID(for: control) == 0 && host.isLiveControl(control) &&
          lineage(window.hitTest(center, with: nil)).contains(where: { $0 === control })
      }
      return true
    }

    func isVisible(control: UIControl? = nil) -> Bool {
      return visibleState(control: control) && root.isAppeared &&
        witnessedAppearanceGeneration == root.appearanceGeneration &&
        witnessedVisibilityGeneration == visibilityGeneration &&
        frameTimestamps.count == 2 && frameTimestamps[0] < frameTimestamps[1] &&
        frameTimestamps.allSatisfy { $0 > max(finalLayoutAt, root.appearedAt) }
    }

    func describe(control: UIControl? = nil) -> String {
      let actual = control ?? mappedControl(in: host.tabBar)
      let source: UIView = actual ?? host.tabBar
      let rect = source.convert(source.bounds, to: window)
      let hit = window.hitTest(CGPoint(x: rect.midX, y: rect.midY), with: nil)
      let ancestors = lineage(source).map {
        "id=\(Self.id($0)),hidden=\($0.isHidden),alpha=\($0.alpha),inWindow=\($0.convert($0.bounds, to: window))"
      }.joined(separator: " -> ")
      let hitIDs = lineage(hit).map { Self.id($0) }.joined(separator: " -> ")
      return "\(Self.inventory()) fixtureScene=\(scene.session.persistentIdentifier) " +
        "sceneConnected=\(UIApplication.shared.connectedScenes.contains { $0 === scene }) " +
        "windowMember=\(scene.windows.contains { $0 === window }) windowSceneMatches=\(window.windowScene === scene) " +
        "windowID=\(Self.id(window)) hidden=\(window.isHidden) alpha=\(window.alpha) key=\(window.isKeyWindow) " +
        "level=\(window.windowLevel.rawValue) window.bounds=\(window.bounds) scene.bounds=\(scene.coordinateSpace.bounds) " +
        "rootID=\(Self.id(root)) actualRoot=\(Self.id(window.rootViewController)) root.parent=\(Self.id(root.parent)) " +
        "root.viewID=\(Self.id(root.view)) root.window=\(Self.id(root.view.window)) " +
        "hostID=\(Self.id(host)) controller.parent=\(Self.id(host.controller.parent)) " +
        "rootAppeared=\(root.appearanceCount) isAppeared=\(root.isAppeared) " +
        "appearanceGeneration=\(root.appearanceGeneration) witnessedAppearance=\(String(describing: witnessedAppearanceGeneration)) " +
        "visibilityGeneration=\(visibilityGeneration) witnessedVisibility=\(String(describing: witnessedVisibilityGeneration)) " +
        "readinessLoss=\(String(reflecting: readinessLoss)) disappearedAt=\(root.disappearedAt) " +
        "appearedAt=\(root.appearedAt) layoutAt=\(finalLayoutAt) frames=\(frameTimestamps) " +
        "sourceID=\(Self.id(actual)) mappedID=\(String(describing: actual.flatMap { host.itemID(for: $0) })) " +
        "source.bounds=\(source.bounds) source.frame=\(source.frame) source.inBar=\(source.convert(source.bounds, to: host.tabBar)) " +
        "source.inWindow=\(rect) bar.inWindow=\(host.tabBar.convert(host.tabBar.bounds, to: window)) " +
        "ancestors=[\(ancestors)] windowHitAncestors=[\(hitIDs)] " +
        "windowHitContainsSource=\(actual.map { source in lineage(hit).contains { $0 === source } } ?? false)"
    }

    func requireVisible(stage: String, control: UIControl? = nil) throws {
      let diagnostic = "NATIVE_VISIBLE_WINDOW stage=\(stage) \(describe(control: control))"
      print(diagnostic)
      guard isVisible(control: control) else {
        XCTFail(diagnostic)
        throw NSError(domain: "NativeVisibleWindow", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: diagnostic])
      }
    }

    /// Both actual timestamps must belong to ONE uninterrupted visible epoch,
    /// after final layout and the CURRENT actual UIKit appearance. Never restart
    /// a failed epoch or retry a draw. The deadline is a failure, not a sleep.
    func awaitVisibleFrames(stage: String) async throws {
      frameTimestamps.removeAll()
      witnessedAppearanceGeneration = nil
      witnessedVisibilityGeneration = nil
      finalLayoutAt = CACurrentMediaTime()
      let observer = DisplayFrameObserver()
      // activeScene and visibleState constrain this link to the main screen.
      let link = CADisplayLink(target: observer, selector: #selector(DisplayFrameObserver.frame(_:)))
      defer { link.invalidate(); observer.onFrame = nil }
      let advanced = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
        var finished = false
        let deadline = DispatchWorkItem { [self] in
          guard !finished else { return }
          finished = true
          loseReadiness("frame-deadline")
          continuation.resume(returning: false)
        }
        observer.onFrame = { [self] frame in
          guard !finished else { return }
          guard visibleState() else {
            loseReadiness("frame-visible-state-lost")
            finished = true
            deadline.cancel()
            continuation.resume(returning: false)
            return
          }
          // Waiting for the FIRST real appearance is allowed. A disappearance
          // at any point is latched by onDisappearance and cannot be recovered.
          guard root.isAppeared else { return }
          if witnessedAppearanceGeneration == nil {
            witnessedAppearanceGeneration = root.appearanceGeneration
            witnessedVisibilityGeneration = visibilityGeneration
          }
          guard witnessedAppearanceGeneration == root.appearanceGeneration,
            witnessedVisibilityGeneration == visibilityGeneration else {
            loseReadiness("frame-epoch-changed")
            finished = true
            deadline.cancel()
            continuation.resume(returning: false)
            return
          }
          let threshold = max(finalLayoutAt, root.appearedAt)
          guard frameTimestamps.allSatisfy({ $0 > threshold }) else {
            loseReadiness("stored-frame-precedes-current-appearance")
            finished = true
            deadline.cancel()
            continuation.resume(returning: false)
            return
          }
          guard frame.timestamp > threshold,
            frame.timestamp > (frameTimestamps.last ?? 0) else { return }
          frameTimestamps.append(frame.timestamp)
          if frameTimestamps.count == 2 {
            finished = true
            deadline.cancel()
            continuation.resume(returning: isVisible())
          }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: deadline)
        link.add(to: .main, forMode: .common)
      }
      guard advanced else {
        let diagnostic = "NATIVE_VISIBLE_WINDOW readiness-failed deadline=8s stage=\(stage) \(describe())"
        print(diagnostic)
        XCTFail(diagnostic)
        throw NSError(domain: "NativeVisibleWindow", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: diagnostic])
      }
      try requireVisible(stage: stage)
    }
  }

  /// Run this separately to capture BOTH directions even while the acceptance
  /// test still throws on its first missing real control. No mapping pass claim.
  @MainActor
  func testDiagnoseRealWindowPublicTabHierarchy() async throws {
    let fixture = try await VisibleTabWindow.make()
    defer { fixture.cleanup() }
    let parent = fixture.root
    let window = fixture.window
    let host = fixture.host
    fixture.makeKeyAndVisible()
    parent.view.layoutIfNeeded()
    var config = try configuration()
    var definitions = try XCTUnwrap(config["items"] as? [[String: Any]])
    definitions[0]["unread"] = 0
    config["items"] = definitions
    config["selectedId"] = 2
    for rtl in [false, true] {
      config["rtl"] = rtl
      host.apply(config)
      for _ in 0..<2 {
        let height = host.naturalHeight(for: parent.view.bounds.width)
        host.frame = CGRect(x: 0, y: parent.view.bounds.height - height,
                            width: parent.view.bounds.width, height: height)
        host.setNeedsLayout()
        host.layoutIfNeeded()
        host.controller.view.layoutIfNeeded()
        host.tabBar.layoutIfNeeded()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
          DispatchQueue.main.async { continuation.resume() }
        }
      }
      let tree = publicTabHierarchy(host, rtl: rtl)
      print(tree)
      let attachment = XCTAttachment(string: tree)
      attachment.name = "NativeTabPublicHierarchy-\(rtl ? "RTL" : "LTR")"
      attachment.lifetime = .keepAlways
      add(attachment)
      try await fixture.awaitVisibleFrames(stage: "hierarchy rtl=\(rtl)")
      XCTAssertTrue(host.controller.parent === parent)
      XCTAssertTrue(host.window === window)
    }
  }

  @MainActor
  func testRealWindowControlHitMappingUnselectedRTLAndHiddenBadge() async throws {
    let fixture = try await VisibleTabWindow.make()
    defer { fixture.cleanup() }
    let parent = fixture.root
    let window = fixture.window
    let host = fixture.host
    fixture.makeKeyAndVisible()
    parent.view.layoutIfNeeded()
    var config = try configuration()
    var definitions = try XCTUnwrap(config["items"] as? [[String: Any]])
    var reads = 0
    var selections = 0
    host.onMarkAllRead = { _, _ in reads += 1 }
    host.onSelect = { _ in selections += 1 }
    for (rtl, unread, selectedID) in [
      (false, 0, 2), (false, 21, 2), (true, 0, 2), (true, 21, 2),
      (false, 21, 0), (true, 21, 0), // also cover the selected Messages runtime failure
    ] {
      config["selectedId"] = selectedID
      definitions[0]["unread"] = unread
      config["items"] = definitions
      config["rtl"] = rtl
      host.apply(config)
      host.layoutIfNeeded()
      let height = host.naturalHeight(for: parent.view.bounds.width)
      host.frame = CGRect(x: 0, y: parent.view.bounds.height - height,
                          width: parent.view.bounds.width, height: height)
      host.setNeedsLayout()
      host.layoutIfNeeded()
      host.controller.view.layoutIfNeeded()
      host.tabBar.layoutIfNeeded()
      // Let UIKit finish deferred containment/RTL work on the real main runloop
      // before asserting the production hit map. Do not inject test controls.
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        DispatchQueue.main.async { continuation.resume() }
      }
      parent.view.layoutIfNeeded()
      let settledHeight = host.naturalHeight(for: parent.view.bounds.width)
      host.frame = CGRect(x: 0, y: parent.view.bounds.height - settledHeight,
                          width: parent.view.bounds.width, height: settledHeight)
      host.setNeedsLayout()
      host.layoutIfNeeded()
      host.controller.view.layoutIfNeeded()
      host.tabBar.layoutIfNeeded()
      let metrics = host.runtimeMetrics()
      XCTAssertLessThan(host.tabBar.bounds.height, host.tabBar.bounds.width,
                        "An embedded footer must stay horizontal in an adaptive window")
      let tree = publicTabHierarchy(host, rtl: rtl)
      print(tree)
      let attachment = XCTAttachment(string: tree)
      attachment.name = "NativeTabAcceptancePublicHierarchy-\(rtl ? "RTL" : "LTR")"
      attachment.lifetime = .keepAlways
      add(attachment)
      // runtimeMetrics/publicTabHierarchy above may force layout. All later
      // diagnostic reads are observational; the ancestor negative below still
      // intentionally exercises explicit layout invalidation.
      try await fixture.awaitVisibleFrames(
        stage: "case=(rtl=\(rtl),unread=\(unread),selectedID=\(selectedID)) final-layout"
      )
      XCTAssertTrue((metrics["mappedContextMenuIds"] as? [Int] ?? []).contains(0),
                    "Production metrics must expose the actual Messages body in both directions")
      // Discover a REAL public UIControl via its public identity, not a
      // fabricated control, private class name, or calculated equal-width slot.
      func controls(in view: UIView) -> [UIControl] {
        var result = (view as? UIControl).map { [$0] } ?? []
        for child in view.subviews { result.append(contentsOf: controls(in: child)) }
        return result
      }
      let actual = try XCTUnwrap(controls(in: host.tabBar).first { control in
        guard host.itemID(for: control) == 0 else { return false }
        let center = control.convert(
          CGPoint(x: control.bounds.midX, y: control.bounds.midY), to: host.tabBar
        )
        var hit = host.tabBar.hitTest(center, with: nil)
        while let current = hit, current !== host.tabBar {
          if current === control { return true }
          hit = current.superview
        }
        return false
      }, "A real hit-test control must expose unique public Messages identity")
      XCTAssertTrue(host.isLiveControl(actual))
      XCTAssertTrue(actual.window === window)
      XCTAssertGreaterThan(actual.bounds.width, 0)
      XCTAssertGreaterThan(actual.bounds.height, 0)
      XCTAssertEqual(actual.accessibilityCustomActions?.first?.name, "Mark all as read")
      let point = actual.convert(CGPoint(x: actual.bounds.midX, y: actual.bounds.midY),
                                 to: host.tabBar)
      XCTAssertEqual(host.contextMenuItem(at: point)?.tag, 0)
      // Real native body padding below the caption is also a target; neither
      // the floating bar's empty edge nor its indicator region is a tab body.
      let paddingPoint = actual.convert(
        CGPoint(x: actual.bounds.midX, y: actual.bounds.maxY - 1), to: host.tabBar
      )
      XCTAssertEqual(host.contextMenuItem(at: paddingPoint)?.tag, 0)
      XCTAssertNil(host.contextMenuItem(at: CGPoint(
        x: host.tabBar.bounds.minX + 1, y: host.tabBar.bounds.midY
      )))
      XCTAssertNil(host.contextMenuItem(at: CGPoint(
        x: host.tabBar.bounds.midX, y: host.tabBar.bounds.maxY - 1
      )))
      let interaction = try XCTUnwrap(host.tabBar.interactions.compactMap {
        $0 as? UIContextMenuInteraction
      }.first { $0.delegate === host })
      let sourceRect = actual.convert(actual.bounds, to: host.tabBar)
      let sourceFrame = actual.frame
      let sourceSuperview = actual.superview
      let sourceAlpha = actual.alpha
      let sourceHidden = actual.isHidden
      let sourceBadge = unread == 0 ? nil : "21"
      XCTAssertEqual(host.tabBar.items?.first?.badgeValue, sourceBadge)
      func liveGeometry() -> String {
        return "source.bounds=\(actual.bounds) source.frame=\(actual.frame) " +
          "source.inBar=\(actual.convert(actual.bounds, to: host.tabBar)) " +
          "source.inWindow=\(actual.convert(actual.bounds, to: window)) " +
          "source.live=\(host.isLiveControl(actual)) source.windowMatches=\(actual.window === window) " +
          "bar.bounds=\(host.tabBar.bounds) bar.frame=\(host.tabBar.frame) " +
          "bar.inWindow=\(host.tabBar.convert(host.tabBar.bounds, to: window)) " +
          "bar.windowMatches=\(host.tabBar.window === window) " +
          "window.bounds=\(window.bounds) window.frame=\(window.frame)"
      }
      // Fixture readiness only: render the real public bar once before any
      // menu is created. The delegate's observed capture still uses false.
      try fixture.requireVisible(stage: "before-readiness rtl=\(rtl) unread=\(unread) selectedID=\(selectedID)",
                                 control: actual)
      let preReadinessGeometry = liveGeometry()
      let readinessFormat = UIGraphicsImageRendererFormat()
      readinessFormat.scale = window.screen.scale
      readinessFormat.opaque = false
      var readinessDrawn = false
      _ = UIGraphicsImageRenderer(bounds: host.tabBar.bounds, format: readinessFormat).image { _ in
        readinessDrawn = host.tabBar.drawHierarchy(
          in: host.tabBar.bounds, afterScreenUpdates: true
        )
      }
      let postReadinessGeometry = liveGeometry()
      let readinessDiagnostic =
        "NATIVE_MAPPING_READINESS case=(rtl=\(rtl),unread=\(unread),selectedID=\(selectedID)) " +
        "drawHierarchy=\(readinessDrawn) " +
        "pre={\(preReadinessGeometry)} post={\(postReadinessGeometry)} " +
        "visibility={\(fixture.describe(control: actual))}"
      print(readinessDiagnostic)
      XCTAssertTrue(readinessDrawn, readinessDiagnostic)
      XCTAssertEqual(preReadinessGeometry, postReadinessGeometry, readinessDiagnostic)
      guard readinessDrawn, preReadinessGeometry == postReadinessGeometry else {
        throw NSError(domain: "NativeMappingReadiness", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: readinessDiagnostic])
      }
      try fixture.requireVisible(stage: "after-readiness rtl=\(rtl) unread=\(unread) selectedID=\(selectedID)",
                                 control: actual)
      var captures = 0
      var drawResults: [Bool] = []
      host.menuHierarchyDrawing = { [weak host] bar, rect, updates in
        captures += 1
        XCTAssertTrue(bar === host?.tabBar)
        XCTAssertEqual(rect, bar.bounds)
        XCTAssertFalse(updates)
        let beforeCapture = fixture.describe(control: actual)
        print("NATIVE_VISIBLE_CAPTURE before case=(rtl=\(rtl),unread=\(unread),selectedID=\(selectedID)) " +
              "capture=\(captures) updates=\(updates) \(beforeCapture)")
        XCTAssertTrue(fixture.isVisible(control: actual), beforeCapture)
        let drawn = bar.drawHierarchy(in: rect, afterScreenUpdates: updates)
        print("NATIVE_VISIBLE_CAPTURE after capture=\(captures) updates=\(updates) drawn=\(drawn) " +
              fixture.describe(control: actual))
        drawResults.append(drawn)
        return drawn
      }
      let menu = try XCTUnwrap(host.contextMenuInteraction(
        interaction, configurationForMenuAtLocation: point
      ))
      fixture.activeMenu = (interaction, menu)
      XCTAssertEqual((menu.identifier as? NSNumber)?.intValue, 0)
      let preHighlightGeometry = liveGeometry()
      let highlightResult = host.contextMenuInteraction(
        interaction, previewForHighlightingMenuWithConfiguration: menu
      )
      let postHighlightGeometry = liveGeometry()
      let preview = try XCTUnwrap(highlightResult,
        "NATIVE_MAPPING_DRAW_DIAGNOSTIC case=(rtl=\(rtl),unread=\(unread),selectedID=\(selectedID)) " +
        "drawHierarchyResults=\(drawResults) captures=\(captures) " +
        "highlightResult=\(highlightResult == nil ? "nil" : "non-nil") " +
        "pre={\(preHighlightGeometry)} post={\(postHighlightGeometry)} " +
        "visibility={\(fixture.describe(control: actual))}")
      XCTAssertFalse(preview.view === actual)
      XCTAssertEqual(preview.parameters.backgroundColor, UIColor.clear)
      XCTAssertNil(preview.view.superview, "The frozen item must never become a source overlay")
      XCTAssertEqual(preview.view.bounds.size, sourceRect.size)
      let imageView = try XCTUnwrap(preview.view as? UIImageView,
        "A detached render-container is insufficient; the preview must own image pixels")
      let image = try XCTUnwrap(imageView.image)
      let pixels = try XCTUnwrap(image.cgImage)
      XCTAssertEqual(image.scale, window.screen.scale)
      XCTAssertEqual(image.size.width, sourceRect.width, accuracy: 1 / image.scale)
      XCTAssertEqual(image.size.height, sourceRect.height, accuracy: 1 / image.scale)
      XCTAssertEqual(CGFloat(pixels.width), sourceRect.width * image.scale, accuracy: 1)
      XCTAssertEqual(CGFloat(pixels.height), sourceRect.height * image.scale, accuracy: 1)
      try assertNativePreviewPixels(image, visibleBadge: unread == 21)
      XCTAssertTrue(preview.target.container === window)
      XCTAssertEqual(preview.target.center, host.tabBar.convert(
        CGPoint(x: sourceRect.midX, y: sourceRect.midY), to: window
      ))
      let dismissal = host.contextMenuInteraction(
        interaction, previewForDismissingMenuWithConfiguration: menu
      )
      XCTAssertTrue(dismissal === preview)
      XCTAssertEqual(captures, 1, "Highlight and dismissal share one frozen native item")
      host.contextMenuInteraction(interaction, willEndFor: menu, animator: nil)
      XCTAssertNil(host.contextMenuInteraction(
        interaction, previewForHighlightingMenuWithConfiguration: menu
      ))
      XCTAssertNil(host.contextMenuInteraction(
        interaction, previewForDismissingMenuWithConfiguration: menu
      ))
      XCTAssertTrue(actual.superview === sourceSuperview)
      XCTAssertEqual(actual.frame, sourceFrame)
      XCTAssertEqual(actual.alpha, sourceAlpha)
      XCTAssertEqual(actual.isHidden, sourceHidden)
      XCTAssertEqual(host.tabBar.items?.first?.badgeValue, sourceBadge)
      // Same-window movement preserves the tab-bar-local crop but invalidates
      // the frozen preview's window target, even before another layout pass.
      let movedMenu = try XCTUnwrap(host.contextMenuInteraction(
        interaction, configurationForMenuAtLocation: point
      ))
      fixture.activeMenu = (interaction, movedMenu)
      XCTAssertNotNil(host.contextMenuInteraction(
        interaction, previewForHighlightingMenuWithConfiguration: movedMenu
      ))
      let sourceWindowRect = actual.convert(actual.bounds, to: window)
      let hostFrame = host.frame
      host.frame.origin.y -= 7
      XCTAssertTrue(host.window === window)
      XCTAssertEqual(actual.convert(actual.bounds, to: host.tabBar), sourceRect)
      XCTAssertNotEqual(actual.convert(actual.bounds, to: window), sourceWindowRect)
      XCTAssertNil(host.contextMenuInteraction(
        interaction, previewForDismissingMenuWithConfiguration: movedMenu
      ))
      host.frame = hostFrame
      XCTAssertNil(host.contextMenuInteraction(
        interaction, previewForHighlightingMenuWithConfiguration: movedMenu
      ), "Restoring window geometry must not revive an invalidated session")
      host.contextMenuInteraction(interaction, willEndFor: movedMenu, animator: nil)

      // Layout validation must also catch ancestor-only movement. Restore the
      // geometry before requesting dismissal to prove layout invalidated it.
      let ancestorMenu = try XCTUnwrap(host.contextMenuInteraction(
        interaction, configurationForMenuAtLocation: point
      ))
      fixture.activeMenu = (interaction, ancestorMenu)
      XCTAssertNotNil(host.contextMenuInteraction(
        interaction, previewForHighlightingMenuWithConfiguration: ancestorMenu
      ))
      let ancestorTransform = parent.view.transform
      parent.view.transform = ancestorTransform.translatedBy(x: 0, y: -9)
      XCTAssertTrue(host.window === window)
      XCTAssertEqual(actual.convert(actual.bounds, to: host.tabBar), sourceRect)
      XCTAssertNotEqual(actual.convert(actual.bounds, to: window), sourceWindowRect)
      host.setNeedsLayout()
      host.layoutIfNeeded()
      parent.view.transform = ancestorTransform
      XCTAssertNil(host.contextMenuInteraction(
        interaction, previewForDismissingMenuWithConfiguration: ancestorMenu
      ), "Ancestor movement must invalidate during layout, not only preview callbacks")
      host.contextMenuInteraction(interaction, willEndFor: ancestorMenu, animator: nil)
      XCTAssertEqual(metrics["selectedId"] as? Int, selectedID)
      XCTAssertEqual(reads, 0)
      XCTAssertEqual(selections, 0)
      XCTAssertEqual(host.controller.selectedViewController?.tabBarItem.tag, selectedID)
      XCTAssertGreaterThan(host.tabBar.bounds.height, 0)
      XCTAssertTrue(host.bounds.contains(host.tabBar.convert(host.tabBar.bounds, to: host)))
    }
  }

  @MainActor
  private func assertNativePreviewPixels(_ image: UIImage, visibleBadge: Bool) throws {
    let pixels = try XCTUnwrap(image.cgImage)
    let width = pixels.width
    let height = pixels.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let rendered = bytes.withUnsafeMutableBytes { buffer -> Bool in
      guard let context = CGContext(
        data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
      ) else { return false }
      context.draw(pixels, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
      return true
    }
    XCTAssertTrue(rendered)
    var colors = Set<UInt32>()
    var visible = 0
    var darkest = 255
    var lightest = 0
    var red = 0
    for offset in stride(from: 0, to: bytes.count, by: 4) where bytes[offset + 3] > 128 {
      let r = Int(bytes[offset])
      let g = Int(bytes[offset + 1])
      let b = Int(bytes[offset + 2])
      visible += 1
      colors.insert(UInt32(r << 16 | g << 8 | b))
      let luminance = (r + g + b) / 3
      darkest = min(darkest, luminance)
      lightest = max(lightest, luminance)
      if r > 150 && r > g + 40 && r > b + 40 { red += 1 }
    }
    XCTAssertGreaterThan(visible, 32, "Reject an empty/transparent raster")
    XCTAssertGreaterThan(colors.count, 8, "Reject a solid white (or any uniform) raster")
    XCTAssertGreaterThan(lightest - darkest, 24, "Native artwork must have visible pixel contrast")
    if visibleBadge {
      XCTAssertGreaterThan(red, 10, "The native badge21 must contribute actual red pixels to the crop")
    }
    // This catches absent raster content; it is not optical/menu-animation acceptance.
  }

  /// Fault injection only, separate from the real UIKit-control acceptance
  /// test. The transparent test container isolates synthetic input controls;
  /// its frames are arbitrary fixtures, never production tab hit regions.
  @MainActor
  private func syntheticFaultHost() throws -> (UIWindow, NativeTabBarHost, UIView) {
    let parent = HorizontalBarRoot()
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    window.rootViewController = parent
    window.makeKeyAndVisible()
    parent.view.layoutIfNeeded()
    let host = NativeTabBarHost(frame: CGRect(x: 0, y: 700, width: 390, height: 1))
    parent.view.addSubview(host)
    host.apply(try configuration())
    host.layoutIfNeeded()
    let height = host.naturalHeight(for: 390)
    host.frame = CGRect(x: 0, y: 844 - height, width: 390, height: height)
    host.setNeedsLayout()
    host.layoutIfNeeded()
    let container = UIView(frame: host.tabBar.bounds)
    container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    host.tabBar.addSubview(container)
    return (window, host, container)
  }

  @MainActor
  private final class MenuEndAnimator: NSObject, UIContextMenuInteractionAnimating {
    var previewViewController: UIViewController? { nil }
    var completions: [() -> Void] = []
    func addAnimations(_ animations: @escaping () -> Void) { animations() }
    func addCompletion(_ completion: @escaping () -> Void) { completions.append(completion) }
    func finish() {
      let pending = completions
      completions.removeAll()
      pending.forEach { $0() }
    }
  }

  @MainActor
  func testSnapshotFailureAndForeignConfigurationNeverLiftLiveControl() throws {
    let (window, host, container) = try syntheticFaultHost()
    defer { host.detachController(); window.isHidden = true }
    let control = UIControl(frame: CGRect(x: 20, y: 10, width: 40, height: 30))
    control.accessibilityIdentifier = "bottom-tab-0"
    container.addSubview(control)
    let point = control.convert(CGPoint(x: control.bounds.midX, y: control.bounds.midY),
                                to: host.tabBar)
    let interaction = try XCTUnwrap(host.tabBar.interactions.compactMap {
      $0 as? UIContextMenuInteraction
    }.first { $0.delegate === host })
    let menu = try XCTUnwrap(host.contextMenuInteraction(
      interaction, configurationForMenuAtLocation: point
    ))
    let foreign = UIContextMenuConfiguration(
      identifier: NSNumber(value: 0), previewProvider: nil, actionProvider: nil
    )
    var captures = 0
    host.menuHierarchyDrawing = { _, _, _ in captures += 1; return false }
    XCTAssertNil(host.contextMenuInteraction(
      interaction, previewForHighlightingMenuWithConfiguration: foreign
    ))
    XCTAssertEqual(captures, 0, "A matching numeric ID is not a matching configuration")
    XCTAssertNil(host.contextMenuInteraction(
      interaction, previewForHighlightingMenuWithConfiguration: menu
    ))
    XCTAssertEqual(captures, 1)
    host.menuHierarchyDrawing = { _, _, _ in true }
    XCTAssertNil(host.contextMenuInteraction(
      interaction, previewForDismissingMenuWithConfiguration: menu
    ), "A failed capture cannot later fall back to the live control or revive the session")
    XCTAssertTrue(control.superview === container)
    XCTAssertFalse(control.isHidden)
    XCTAssertEqual(control.alpha, 1)
  }

  @MainActor
  func testSnapshotSessionsRejectChangedSourceAndConfiguration() throws {
    for fault in ["ambiguous", "remapped", "nonlive", "geometry", "itemIdentity", "retagged",
                  "update", "epoch", "route", "removed", "dispose"] {
      let (window, host, container) = try syntheticFaultHost()
      defer { host.detachController(); window.isHidden = true }
      let control = UIControl(frame: CGRect(x: 20, y: 10, width: 40, height: 30))
      control.accessibilityIdentifier = "bottom-tab-0"
      container.addSubview(control)
      let point = control.convert(CGPoint(x: control.bounds.midX, y: control.bounds.midY),
                                  to: host.tabBar)
      let interaction = try XCTUnwrap(host.tabBar.interactions.compactMap {
        $0 as? UIContextMenuInteraction
      }.first { $0.delegate === host })
      var captures = 0
      host.menuHierarchyDrawing = { _, _, _ in captures += 1; return true }
      let menu = try XCTUnwrap(host.contextMenuInteraction(
        interaction, configurationForMenuAtLocation: point
      ))
      XCTAssertNotNil(host.contextMenuInteraction(
        interaction, previewForHighlightingMenuWithConfiguration: menu
      ))
      let selection = host.controller.selectedViewController?.tabBarItem.tag
      var reads = 0
      var selections = 0
      host.onMarkAllRead = { _, _ in reads += 1 }
      host.onSelect = { _ in selections += 1 }
      var config = try configuration()
      let copy = UIControl(frame: CGRect(x: 90, y: 10, width: 40, height: 30))
      switch fault {
      case "ambiguous":
        copy.accessibilityIdentifier = "bottom-tab-0"
        container.addSubview(copy)
      case "remapped": control.accessibilityIdentifier = "bottom-tab-2"
      case "nonlive": control.isUserInteractionEnabled = false
      case "geometry": control.frame.origin.x += 1
      case "itemIdentity":
        let replacement = UITabBarItem(title: "Messages", image: nil, tag: 0)
        replacement.accessibilityIdentifier = "bottom-tab-0"
        host.controller.viewControllers?.first?.tabBarItem = replacement
      case "retagged": host.tabBar.items?.first?.tag = 2
      case "update": host.apply(config) // same epoch still invalidates frozen appearance
      case "epoch": config["actionEpoch"] = 2; host.apply(config)
      case "route": config["selectedId"] = 2; host.apply(config)
      case "removed": config["items"] = []; host.apply(config)
      case "dispose": host.detachController()
      default: XCTFail("Unknown fault")
      }
      XCTAssertNil(host.contextMenuInteraction(
        interaction, previewForHighlightingMenuWithConfiguration: menu
      ), fault)
      XCTAssertNil(host.contextMenuInteraction(
        interaction, previewForDismissingMenuWithConfiguration: menu
      ), fault)
      // Restoring the same public ID/control cannot resurrect an invalidated
      // configuration, even when its action epoch did not change.
      copy.removeFromSuperview()
      control.accessibilityIdentifier = "bottom-tab-0"
      control.isUserInteractionEnabled = true
      control.frame.origin.x = 20
      XCTAssertNil(host.contextMenuInteraction(
        interaction, previewForHighlightingMenuWithConfiguration: menu
      ), fault)
      XCTAssertEqual(captures, 1, fault)
      XCTAssertEqual(reads, 0, fault)
      XCTAssertEqual(selections, 0, fault)
      if ["ambiguous", "remapped", "nonlive", "geometry", "update"].contains(fault) {
        XCTAssertEqual(host.controller.selectedViewController?.tabBarItem.tag, selection, fault)
      }
      host.contextMenuInteraction(interaction, willEndFor: menu, animator: nil)
    }
  }

  @MainActor
  func testSnapshotLifetimeEndAnimationDisposalAndSameIDNewSession() throws {
    let (window, host, container) = try syntheticFaultHost()
    defer { host.detachController(); window.isHidden = true }
    let control = UIControl(frame: CGRect(x: 20, y: 10, width: 40, height: 30))
    control.accessibilityIdentifier = "bottom-tab-0"
    container.addSubview(control)
    let point = control.convert(CGPoint(x: control.bounds.midX, y: control.bounds.midY),
                                to: host.tabBar)
    let interaction = try XCTUnwrap(host.tabBar.interactions.compactMap {
      $0 as? UIContextMenuInteraction
    }.first { $0.delegate === host })
    weak var snapshot: UIView?
    host.menuHierarchyDrawing = { _, _, _ in true } // lifetime-only fault fixture
    func open() throws -> UIContextMenuConfiguration {
      try XCTUnwrap(host.contextMenuInteraction(interaction, configurationForMenuAtLocation: point))
    }
    func highlight(_ menu: UIContextMenuConfiguration) -> UITargetedPreview? {
      let preview = host.contextMenuInteraction(
        interaction, previewForHighlightingMenuWithConfiguration: menu
      )
      if let preview { snapshot = preview.view }
      return preview
    }
    let first = try open()
    XCTAssertNotNil(highlight(first))
    XCTAssertNotNil(snapshot, "The configuration must retain its snapshot between callbacks")
    weak var firstSnapshot = snapshot
    let animator = MenuEndAnimator()
    host.contextMenuInteraction(interaction, willEndFor: first, animator: animator)
    XCTAssertNotNil(snapshot, "Do not release the view before the end animation completes")
    let second = try open() // same numeric identifier; distinct configuration/session
    XCTAssertNil(highlight(first))
    XCTAssertNotNil(highlight(second))
    weak var secondSnapshot = snapshot
    animator.finish() // ending the old session must not clear the newer one
    XCTAssertNil(firstSnapshot)
    XCTAssertTrue(host.contextMenuInteraction(
      interaction, previewForDismissingMenuWithConfiguration: second
    )?.view === secondSnapshot)
    host.apply(try configuration())
    XCTAssertNil(highlight(second))
    XCTAssertNotNil(secondSnapshot, "Invalidation must preserve UIKit's ending visual")
    let invalidatedAnimator = MenuEndAnimator()
    host.contextMenuInteraction(interaction, willEndFor: second, animator: invalidatedAnimator)
    invalidatedAnimator.finish()
    XCTAssertNil(secondSnapshot, "Release the frozen view on animation completion")
    let third = try open()
    XCTAssertNotNil(highlight(third))
    weak var thirdSnapshot = snapshot
    host.contextMenuInteraction(interaction, willEndFor: third, animator: nil)
    XCTAssertNil(thirdSnapshot, "A nonanimated end releases immediately")
    weak var disposedSnapshot: UIView?
    try autoreleasepool {
      var disposed: UIContextMenuConfiguration? = try open()
      XCTAssertNotNil(highlight(try XCTUnwrap(disposed)))
      disposedSnapshot = snapshot
      disposed = nil // UIKit can discard a configuration before presentation, without willEnd
    }
    XCTAssertNil(disposedSnapshot, "The host must not retain a discarded configuration/session")
  }

  @MainActor
  func testTwoLiveControlsFailClosedButNonHitVisualCopyDoesNot() throws {
    let (window, host, container) = try syntheticFaultHost()
    defer { host.detachController(); window.isHidden = true }
    let first = UIControl(frame: CGRect(x: 20, y: 10, width: 40, height: 30))
    first.accessibilityIdentifier = "bottom-tab-0"
    let foreign = UIAccessibilityCustomAction(name: "Mark all as read") { _ in true }
    first.accessibilityCustomActions = [foreign]
    container.addSubview(first)
    let copy = UIControl(frame: first.frame)
    copy.accessibilityIdentifier = "bottom-tab-0"
    copy.isUserInteractionEnabled = false
    container.addSubview(copy)
    let point = first.convert(CGPoint(x: first.bounds.midX, y: first.bounds.midY), to: host.tabBar)
    let interaction = try XCTUnwrap(host.tabBar.interactions.compactMap {
      $0 as? UIContextMenuInteraction
    }.first { $0.delegate === host })
    XCTAssertTrue(host.isLiveControl(first))
    XCTAssertFalse(host.isLiveControl(copy))
    XCTAssertEqual(host.contextMenuItem(at: point)?.tag, 0)
    XCTAssertNotNil(host.contextMenuInteraction(interaction, configurationForMenuAtLocation: point))
    XCTAssertTrue((host.runtimeMetrics()["mappedContextMenuIds"] as? [Int] ?? []).contains(0))
    let original = try XCTUnwrap(first.accessibilityCustomActions?.first { $0 !== foreign })
    let itemAction = try XCTUnwrap(host.tabBar.items?.first?.accessibilityCustomActions?.first)
    var reads = 0
    host.onMarkAllRead = { _, _ in reads += 1 }
    copy.frame.origin.x = 90
    copy.isUserInteractionEnabled = true
    XCTAssertTrue(host.isLiveControl(first))
    XCTAssertTrue(host.isLiveControl(copy))
    XCTAssertNil(host.contextMenuItem(at: point))
    XCTAssertNil(host.contextMenuInteraction(interaction, configurationForMenuAtLocation: point))
    XCTAssertFalse(try XCTUnwrap(original.actionHandler)(original))
    XCTAssertFalse(try XCTUnwrap(itemAction.actionHandler)(itemAction))
    XCTAssertFalse((host.runtimeMetrics()["mappedContextMenuIds"] as? [Int] ?? []).contains(0))
    XCTAssertEqual(first.accessibilityCustomActions?.count, 1)
    XCTAssertTrue(first.accessibilityCustomActions?.first === foreign)
    copy.isUserInteractionEnabled = false
    XCTAssertEqual(host.contextMenuItem(at: point)?.tag, 0)
    XCTAssertTrue((host.runtimeMetrics()["mappedContextMenuIds"] as? [Int] ?? []).contains(0))
    XCTAssertFalse(try XCTUnwrap(original.actionHandler)(original))
    XCTAssertEqual(reads, 0)
  }

  @MainActor
  func testOwnedAccessibilityActionRevokesRemappedAmbiguousAndNonLiveControl() throws {
    let (window, host, container) = try syntheticFaultHost()
    defer { host.detachController(); window.isHidden = true }
    let control = UIControl(frame: CGRect(x: 20, y: 10, width: 40, height: 30))
    let title = UILabel()
    title.text = "Messages"
    control.addSubview(title)
    let foreign = UIAccessibilityCustomAction(name: "Mark all as read") { _ in true }
    control.accessibilityCustomActions = [foreign]
    container.addSubview(control)
    var reads = 0
    host.onMarkAllRead = { _, _ in reads += 1 }
    func installedRead() throws -> UIAccessibilityCustomAction {
      _ = host.runtimeMetrics()
      XCTAssertTrue(control.accessibilityCustomActions?.contains(where: { $0 === foreign }) == true)
      return try XCTUnwrap(control.accessibilityCustomActions?.first { $0 !== foreign })
    }
    func invoke(_ action: UIAccessibilityCustomAction) throws -> Bool {
      try XCTUnwrap(action.actionHandler)(action)
    }
    let original = try installedRead()
    title.text = "Unknown"
    XCTAssertFalse(try invoke(original)) // rejects even BEFORE next layout cleanup
    _ = host.runtimeMetrics()
    XCTAssertEqual(control.accessibilityCustomActions?.count, 1)
    XCTAssertTrue(control.accessibilityCustomActions?.first === foreign)
    title.text = "Messages"
    let replacement = try installedRead()
    XCTAssertFalse(try invoke(original)) // same epoch + restored title cannot revive token
    let secondTitle = UILabel()
    secondTitle.text = "Contacts"
    control.addSubview(secondTitle)
    XCTAssertFalse(try invoke(replacement))
    _ = host.runtimeMetrics()
    XCTAssertEqual(control.accessibilityCustomActions?.count, 1)
    XCTAssertTrue(control.accessibilityCustomActions?.first === foreign)
    secondTitle.removeFromSuperview()
    let beforeNonLive = try installedRead()
    control.isUserInteractionEnabled = false
    XCTAssertFalse(try invoke(beforeNonLive))
    _ = host.runtimeMetrics()
    XCTAssertEqual(control.accessibilityCustomActions?.count, 1)
    XCTAssertTrue(control.accessibilityCustomActions?.first === foreign)
    control.isUserInteractionEnabled = true
    let current = try installedRead()
    XCTAssertFalse(try invoke(beforeNonLive))
    XCTAssertEqual(reads, 0)
    XCTAssertTrue(try invoke(current))
    XCTAssertTrue(try invoke(current))
    XCTAssertEqual(reads, 1)
    control.removeFromSuperview()
    XCTAssertFalse(try invoke(current))
    _ = host.runtimeMetrics()
    XCTAssertEqual(control.accessibilityCustomActions?.count, 1)
    XCTAssertTrue(control.accessibilityCustomActions?.first === foreign)
    container.addSubview(control)
    _ = try installedRead()
    XCTAssertFalse(try invoke(current))
    XCTAssertEqual(reads, 1)
  }

  @MainActor
  func testFreshUnreadConfigurationRearmsControlActionWithoutChangingEpoch() throws {
    let (window, host, container) = try syntheticFaultHost()
    defer { host.detachController(); window.isHidden = true }
    let control = UIControl(frame: CGRect(x: 20, y: 10, width: 40, height: 30))
    control.accessibilityIdentifier = "bottom-tab-0"
    let foreign = UIAccessibilityCustomAction(name: "Mark all as read") { _ in true }
    control.accessibilityCustomActions = [foreign]
    container.addSubview(control)
    _ = host.runtimeMetrics()
    let original = try XCTUnwrap(control.accessibilityCustomActions?.first { $0 !== foreign })
    let originalItemAction = try XCTUnwrap(host.tabBar.items?.first?.accessibilityCustomActions?.first)
    var reads = 0
    host.onMarkAllRead = { _, _ in reads += 1 }
    XCTAssertTrue(try XCTUnwrap(original.actionHandler)(original))
    XCTAssertTrue(try XCTUnwrap(original.actionHandler)(original))
    XCTAssertEqual(reads, 1)
    _ = host.runtimeMetrics()
    XCTAssertTrue(control.accessibilityCustomActions?.contains(where: { $0 === original }) == true)
    XCTAssertTrue(try XCTUnwrap(original.actionHandler)(original))
    XCTAssertEqual(reads, 1) // layout alone cannot rearm the consumed request

    var config = try configuration()
    var definitions = try XCTUnwrap(config["items"] as? [[String: Any]])
    definitions[0]["unread"] = 7 // newly arriving unread; same id/epoch/title
    config["items"] = definitions
    host.apply(config)
    XCTAssertFalse(try XCTUnwrap(original.actionHandler)(original))
    XCTAssertFalse(try XCTUnwrap(originalItemAction.actionHandler)(originalItemAction))
    _ = host.runtimeMetrics()
    let current = try XCTUnwrap(control.accessibilityCustomActions?.first { $0 !== foreign })
    XCTAssertFalse(current === original)
    XCTAssertTrue(control.accessibilityCustomActions?.contains(where: { $0 === foreign }) == true)
    XCTAssertTrue(try XCTUnwrap(current.actionHandler)(current))
    XCTAssertTrue(try XCTUnwrap(current.actionHandler)(current))
    XCTAssertEqual(reads, 2)
    _ = host.runtimeMetrics()
    XCTAssertTrue(control.accessibilityCustomActions?.contains(where: { $0 === current }) == true)
    XCTAssertTrue(try XCTUnwrap(current.actionHandler)(current))
    XCTAssertFalse(try XCTUnwrap(original.actionHandler)(original))
    XCTAssertEqual(reads, 2)
  }

  @MainActor
  func testAccessibilityActionsRejectOldEpochAndPreserveForeignItemActions() throws {
    let (window, host, container) = try syntheticFaultHost()
    defer { host.detachController(); window.isHidden = true }
    let control = UIControl(frame: CGRect(x: 20, y: 10, width: 40, height: 30))
    control.accessibilityIdentifier = "bottom-tab-0"
    container.addSubview(control)
    _ = host.runtimeMetrics()
    let oldControlAction = try XCTUnwrap(control.accessibilityCustomActions?.first)
    let item = try XCTUnwrap(host.tabBar.items?.first)
    let oldItemAction = try XCTUnwrap(item.accessibilityCustomActions?.first)
    let foreign = UIAccessibilityCustomAction(name: "Mark all as read") { _ in true }
    item.accessibilityCustomActions = (item.accessibilityCustomActions ?? []) + [foreign]
    var reads = 0
    host.onMarkAllRead = { _, _ in reads += 1 }
    var config = try configuration()
    config["actionEpoch"] = 2
    host.apply(config)
    XCTAssertFalse(try XCTUnwrap(oldControlAction.actionHandler)(oldControlAction))
    XCTAssertFalse(try XCTUnwrap(oldItemAction.actionHandler)(oldItemAction))
    _ = host.runtimeMetrics()
    XCTAssertTrue(item.accessibilityCustomActions?.contains(where: { $0 === foreign }) == true)
    XCTAssertFalse(item.accessibilityCustomActions?.contains(where: { $0 === oldItemAction }) == true)
    let current = try XCTUnwrap(control.accessibilityCustomActions?.first)
    XCTAssertTrue(try XCTUnwrap(current.actionHandler)(current))
    XCTAssertTrue(try XCTUnwrap(current.actionHandler)(current))
    XCTAssertEqual(reads, 1)
  }

  @MainActor
  func testPublicTitleFallbackUsesUniqueExactLabelsAndRejectsConflictingIdentity() throws {
    let host = NativeTabBarHost(frame: .zero)
    var config = try configuration()
    host.apply(config)
    let control = UIControl()
    let wrapper = UIView()
    let title = UILabel()
    title.text = "Messages"
    wrapper.addSubview(title)
    control.addSubview(wrapper)
    XCTAssertEqual(host.itemID(for: control), 0)
    // This fixture intentionally has identical artwork for both items: title
    // identity, never image shape/pointer/order, must distinguish these tabs.
    title.text = "Unknown"
    XCTAssertNil(host.itemID(for: control))
    title.attributedText = NSAttributedString(string: "Messages")
    XCTAssertEqual(host.itemID(for: control), 0)
    control.accessibilityIdentifier = "unrelated-control"
    XCTAssertNil(host.itemID(for: control))
    let items = try XCTUnwrap(host.tabBar.items)
    items.forEach { $0.accessibilityIdentifier = "ambiguous-id" }
    control.accessibilityIdentifier = "ambiguous-id"
    XCTAssertNil(host.itemID(for: control)) // no title fallback for ambiguous IDs
    host.apply(config) // restore stable configured identifiers
    control.accessibilityIdentifier = nil
    control.accessibilityLabel = "Contacts"
    XCTAssertEqual(host.itemID(for: control), 2) // public accessibility label wins
    control.accessibilityLabel = "Unknown"
    XCTAssertNil(host.itemID(for: control))
    control.accessibilityLabel = ""
    XCTAssertNil(host.itemID(for: control))
    control.accessibilityLabel = nil
    let otherTitle = UILabel()
    otherTitle.text = "Contacts"
    wrapper.addSubview(otherTitle)
    XCTAssertNil(host.itemID(for: control)) // two different matching tab titles
    otherTitle.removeFromSuperview()
    var definitions = try XCTUnwrap(config["items"] as? [[String: Any]])
    definitions[1]["label"] = "Messages"
    config["items"] = definitions
    host.apply(config)
    XCTAssertNil(host.itemID(for: control)) // duplicate configured titles
    control.accessibilityLabel = "Messages"
    XCTAssertNil(host.itemID(for: control)) // duplicate accessibility labels
    control.accessibilityLabel = nil
    control.accessibilityIdentifier = "bottom-tab-0"
    XCTAssertEqual(host.itemID(for: control), 0) // explicit stable ID takes priority
    control.accessibilityIdentifier = nil
    config["items"] = [definitions[1]]
    host.apply(config)
    XCTAssertEqual(host.itemID(for: control), 2) // current configured IDs only
    title.text = "messages"
    XCTAssertNil(host.itemID(for: control)) // no case folding or fuzzy identity
  }

  @MainActor
  func testPublicControlMappingRejectsUnidentifiedAmbiguousAndRemovedTabs() throws {
    let host = NativeTabBarHost(frame: .zero)
    var config = try configuration()
    host.apply(config)
    let control = UIControl()
    XCTAssertNil(host.itemID(for: control))
    control.accessibilityIdentifier = "bottom-tab-0"
    XCTAssertEqual(host.itemID(for: control), 0)
    control.accessibilityIdentifier = "unrelated-control"
    control.accessibilityLabel = "Messages"
    XCTAssertNil(host.itemID(for: control))
    control.accessibilityIdentifier = nil
    XCTAssertEqual(host.itemID(for: control), 0)
    var definitions = try XCTUnwrap(config["items"] as? [[String: Any]])
    definitions[1]["label"] = "Messages"
    config["items"] = definitions
    host.apply(config)
    XCTAssertNil(host.itemID(for: control))
    config["items"] = [definitions[1]]
    control.accessibilityIdentifier = "bottom-tab-0"
    host.apply(config)
    XCTAssertNil(host.itemID(for: control))
  }
}
