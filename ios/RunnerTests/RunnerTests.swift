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
