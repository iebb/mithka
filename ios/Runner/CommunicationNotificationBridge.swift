import Flutter
import Intents
import UIKit
import UserNotifications

@available(iOS 15.0, *)
struct CommunicationNotificationRequest {
  let identifier: String
  let title: String
  let body: String
  let conversationIdentifier: String
  let senderName: String
  let payload: String
  let groupConversation: Bool
  let playSound: Bool
  let chatIconPath: String?
  let chatId: Int64?

  init?(arguments: Any?) {
    guard
      let arguments = arguments as? [String: Any],
      let id = arguments["id"] as? NSNumber,
      let title = arguments["title"] as? String,
      let body = arguments["body"] as? String,
      let conversationIdentifier = arguments["conversation_identifier"] as? String,
      let payload = arguments["payload"] as? String
    else {
      return nil
    }

    identifier = "mithka.communication.\(id.intValue)"
    self.title = title
    self.body = body
    self.conversationIdentifier = conversationIdentifier
    senderName = arguments["sender_name"] as? String ?? title
    self.payload = payload
    groupConversation = arguments["group_conversation"] as? Bool ?? false
    playSound = arguments["play_sound"] as? Bool ?? true
    chatIconPath = arguments["chat_icon_path"] as? String
    chatId = (arguments["chat_id"] as? NSNumber)?.int64Value
  }

  func baseContent() -> UNMutableNotificationContent {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.threadIdentifier = conversationIdentifier
    content.sound = playSound ? .default : nil
    content.userInfo = [
      "payload": payload,
      "mithka_communication_notification": true,
    ]
    return content
  }

  func messageIntent() -> INSendMessageIntent {
    information().messageIntent()
  }

  func information() -> CommunicationNotificationInformation {
    CommunicationNotificationInformation(
      title: title,
      body: body,
      conversationIdentifier: conversationIdentifier,
      senderName: senderName,
      groupConversation: groupConversation,
      avatarData: chatIconData()
    )
  }

  private func chatIconData() -> Data? {
    guard
      let chatIconPath,
      !chatIconPath.isEmpty
    else {
      return nil
    }
    if let chatId {
      return NotificationAvatarStore.cacheAvatar(at: chatIconPath, chatId: chatId)
    }
    guard
      let data = try? Data(contentsOf: URL(fileURLWithPath: chatIconPath)),
      !data.isEmpty,
      UIImage(data: data) != nil
    else {
      return nil
    }
    return data
  }
}

@MainActor
final class CommunicationNotificationBridge {
  private let channel: FlutterMethodChannel
  private let notificationCenter: UNUserNotificationCenter

  init(
    messenger: FlutterBinaryMessenger,
    notificationCenter: UNUserNotificationCenter = .current()
  ) {
    channel = FlutterMethodChannel(
      name: "mithka/communication_notifications",
      binaryMessenger: messenger
    )
    self.notificationCenter = notificationCenter
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "cacheChatIcon" {
      guard
        let arguments = call.arguments as? [String: Any],
        let chatId = arguments["chat_id"] as? NSNumber,
        let path = arguments["chat_icon_path"] as? String,
        !path.isEmpty
      else {
        result(
          FlutterError(
            code: "invalid_notification_avatar",
            message: "A chat id and avatar path are required.",
            details: nil
          )
        )
        return
      }
      result(NotificationAvatarStore.cacheAvatar(at: path, chatId: chatId.int64Value) != nil)
      return
    }
    guard call.method == "show" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let request = CommunicationNotificationRequest(arguments: call.arguments) else {
      result(
        FlutterError(
          code: "invalid_communication_notification",
          message: "Missing required communication notification fields.",
          details: nil
        )
      )
      return
    }

    Task { @MainActor in
      let content = request.baseContent()
      let deliveredContent: UNNotificationContent
      do {
        deliveredContent = try await request.information().enrichedContent(from: content)
      } catch {
        NSLog("Mithka communication notification enrichment failed: %@", error.localizedDescription)
        deliveredContent = content
      }

      do {
        try await notificationCenter.add(
          UNNotificationRequest(
            identifier: request.identifier,
            content: deliveredContent,
            trigger: nil
          )
        )
        result(nil)
      } catch {
        result(
          FlutterError(
            code: "communication_notification_failed",
            message: error.localizedDescription,
            details: nil
          )
        )
      }
    }
  }
}
