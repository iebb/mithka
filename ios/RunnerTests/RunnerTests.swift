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


// MARK: - Video note crop maths

/// Pure orientation/crop maths behind `cropVideoNote`: no device, no encoder.
/// `AppDelegate` is main-actor isolated, so the maths is exercised on the main
/// actor too rather than reaching across isolation in a synchronous test.
@MainActor
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

  /// The transform a camera writes for a given sensor orientation.
  private func transform(for degrees: Int, display: CGSize) -> CGAffineTransform {
    switch degrees {
    case 0:
      return .identity
    case 90:
      // Portrait sensor: natural (w,h) is displayed as (h,w).
      return CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 0, ty: display.width)
    case 180:
      return CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: display.width, ty: display.height)
    case 270:
      return CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: display.height, ty: 0)
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
      transform: transform(for: 90, display: CGSize(width: 1280, height: 720)),
      expectedSide: 720,
      expectedOrigin: CGPoint(x: 0, y: 0)
    )
  }

  func testUpsideDownRecordingKeepsTheSquareInsideTheFrame() {
    let transform = self.transform(for: 180, display: CGSize(width: 1280, height: 720))
    let crop = AppDelegate.centredSquareCrop(
      naturalSize: CGSize(width: 1280, height: 720),
      transform: transform
    )
    XCTAssertEqual(crop.side, 720, accuracy: tolerance)
    // A 180-degree rotation moves the frame's origin to (1280, 720); the
    // centred square must still start one margin in, never outside the frame.
    XCTAssertEqual(crop.rect.minX, 280, accuracy: tolerance)
    XCTAssertEqual(crop.rect.minY, 0, accuracy: tolerance)
  }

  func testQuarterTurnTheOtherWayIsMirroredCorrectly() {
    assertCentredSquare(
      natural: CGSize(width: 720, height: 1280),
      transform: transform(for: 270, display: CGSize(width: 720, height: 1280)),
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
  func testLayerTransformMapsTheSquareCornerToTheOrigin() {
    let natural = CGSize(width: 1280, height: 720)
    let transform = self.transform(for: 90, display: CGSize(width: 1280, height: 720))
    let crop = AppDelegate.centredSquareCrop(naturalSize: natural, transform: transform)
    let layer = transform.concatenating(
      CGAffineTransform(translationX: -crop.rect.origin.x, y: -crop.rect.origin.y)
    )
    let mapped = CGRect(origin: .zero, size: natural).applying(layer).standardized
    XCTAssertEqual(mapped.minX, 0, accuracy: tolerance)
    XCTAssertEqual(mapped.minY, 0, accuracy: tolerance)
    XCTAssertEqual(mapped.width, crop.side, accuracy: tolerance)
    XCTAssertEqual(mapped.height, crop.side, accuracy: tolerance)
  }
}
}
