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
    let avatar = chatIconImage()
    let senderHandle = INPersonHandle(
      value: "mithka-chat:\(conversationIdentifier)",
      type: .unknown
    )
    let sender = INPerson(
      personHandle: senderHandle,
      nameComponents: nil,
      displayName: senderName,
      image: groupConversation ? nil : avatar,
      contactIdentifier: nil,
      customIdentifier: "mithka-chat:\(conversationIdentifier)",
      isMe: false,
      suggestionType: .none
    )
    let groupName = groupConversation
      ? INSpeakableString(spokenPhrase: title)
      : nil
    let intent = INSendMessageIntent(
      recipients: nil,
      outgoingMessageType: .outgoingMessageText,
      content: body,
      speakableGroupName: groupName,
      conversationIdentifier: conversationIdentifier,
      serviceName: "Mithka",
      sender: sender,
      attachments: nil
    )
    if groupConversation, let avatar {
      intent.setImage(avatar, forParameterNamed: \.speakableGroupName)
    }
    return intent
  }

  private func chatIconImage() -> INImage? {
    guard
      let chatIconPath,
      !chatIconPath.isEmpty,
      let data = try? Data(contentsOf: URL(fileURLWithPath: chatIconPath)),
      !data.isEmpty,
      UIImage(data: data) != nil
    else {
      return nil
    }
    return INImage(imageData: data)
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
      let intent = request.messageIntent()
      let interaction = INInteraction(intent: intent, response: nil)
      interaction.direction = .incoming

      do {
        try await interaction.donate()
      } catch {
        // Donation improves Focus and suggestion behavior, but a transient
        // donation failure must not discard an otherwise valid chat avatar.
        NSLog("Mithka communication notification donation failed: %@", error.localizedDescription)
      }

      let deliveredContent: UNNotificationContent
      do {
        deliveredContent = try content.updating(from: intent)
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
