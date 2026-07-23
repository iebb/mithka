import Flutter
import Intents
import UIKit
import UserNotifications
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

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
