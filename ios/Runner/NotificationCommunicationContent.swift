import Foundation
import Intents
import UIKit
import UserNotifications

let mithkaNotificationAppGroup = "group.ad.neko.mithka.notifications"

@available(iOS 15.0, *)
struct CommunicationNotificationInformation {
  let title: String
  let body: String
  let conversationIdentifier: String
  let senderName: String
  let groupConversation: Bool
  let avatarData: Data?

  func messageIntent() -> INSendMessageIntent {
    let avatar = avatarData.flatMap(INImage.init(imageData:))
    let senderIdentifier = "mithka-sender:\(conversationIdentifier)"
    let sender = INPerson(
      personHandle: INPersonHandle(value: senderIdentifier, type: .unknown),
      nameComponents: nil,
      displayName: senderName,
      image: groupConversation ? nil : avatar,
      contactIdentifier: nil,
      customIdentifier: senderIdentifier,
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
    if let avatar {
      if groupConversation {
        intent.setImage(avatar, forParameterNamed: \.speakableGroupName)
      } else {
        // Keep the image on both INPerson and the intent parameter. The latter
        // survives intent serialization on iOS versions that otherwise drop
        // an image created from application-container data.
        intent.setImage(avatar, forParameterNamed: \.sender)
      }
    }
    return intent
  }

  func enrichedContent(from content: UNNotificationContent) async throws -> UNNotificationContent {
    let intent = messageIntent()
    let interaction = INInteraction(intent: intent, response: nil)
    interaction.direction = .incoming
    // Donation improves Focus and suggestions, but enrichment itself can still
    // produce the communication avatar if donation is temporarily unavailable.
    try? await interaction.donate()
    return try content.updating(from: intent)
  }
}

enum NotificationAvatarStore {
  private static let directoryName = "NotificationAvatars"
  private static let maximumAvatarCount = 256
  private static let avatarSide = 128

  static func cacheAvatar(at path: String, chatId: Int64) -> Data? {
    guard
      !path.isEmpty,
      let source = UIImage(contentsOfFile: path),
      let data = normalizedData(from: source)
    else {
      return nil
    }
    guard let url = avatarURL(chatId: chatId, createDirectory: true) else {
      return data
    }
    do {
      try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
      pruneIfNeeded(in: url.deletingLastPathComponent())
    } catch {
      // The in-process notification can still use the normalized data even if
      // an app-group entitlement or a temporary file operation is unavailable.
    }
    return data
  }

  static func avatarData(chatId: Int64) -> Data? {
    guard let url = avatarURL(chatId: chatId, createDirectory: false) else {
      return nil
    }
    return try? Data(contentsOf: url, options: .mappedIfSafe)
  }

  private static func avatarURL(chatId: Int64, createDirectory: Bool) -> URL? {
    guard
      let container = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: mithkaNotificationAppGroup
      )
    else {
      return nil
    }
    let directory = container.appendingPathComponent(directoryName, isDirectory: true)
    if createDirectory {
      try? FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true,
        attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
      )
    }
    let filename = chatId < 0 ? "n\(-chatId).jpg" : "p\(chatId).jpg"
    return directory.appendingPathComponent(filename, isDirectory: false)
  }

  private static func normalizedData(from image: UIImage) -> Data? {
    let side = CGFloat(avatarSide)
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    format.opaque = true
    let rendered = UIGraphicsImageRenderer(
      size: CGSize(width: side, height: side),
      format: format
    ).image { context in
      UIColor.white.setFill()
      context.fill(CGRect(x: 0, y: 0, width: side, height: side))
      let size = image.size
      guard size.width > 0, size.height > 0 else { return }
      let scale = max(side / size.width, side / size.height)
      let drawSize = CGSize(width: size.width * scale, height: size.height * scale)
      image.draw(
        in: CGRect(
          x: (side - drawSize.width) / 2,
          y: (side - drawSize.height) / 2,
          width: drawSize.width,
          height: drawSize.height
        )
      )
    }
    return rendered.jpegData(compressionQuality: 0.88)
  }

  private static func pruneIfNeeded(in directory: URL) {
    guard
      let urls = try? FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.contentModificationDateKey],
        options: [.skipsHiddenFiles]
      ),
      urls.count > maximumAvatarCount
    else {
      return
    }
    let sorted = urls.sorted {
      let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?
        .contentModificationDate ?? .distantPast
      let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?
        .contentModificationDate ?? .distantPast
      return lhs < rhs
    }
    for url in sorted.prefix(urls.count - maximumAvatarCount) {
      try? FileManager.default.removeItem(at: url)
    }
  }
}

@available(iOS 15.0, *)
struct RemoteCommunicationNotification {
  let information: CommunicationNotificationInformation
  let chatId: Int64

  init?(content: UNNotificationContent, userInfo: [AnyHashable: Any]) {
    let root = Self.stringKeyed(userInfo)
    let data = Self.dictionary(root["data"]) ?? root
    let custom = Self.dictionary(data["custom"])
      ?? Self.dictionary(root["custom"])
      ?? (data["msg_id"] == nil ? nil : data)
    guard let custom, let chat = Self.chatIdentity(from: custom) else {
      return nil
    }
    chatId = chat.chatId

    let locArgs = Self.stringArray(data["loc_args"] ?? root["loc_args"])
    let fallbackTitle = Self.firstNonEmpty([
      content.title,
      data["title"],
      root["title"],
      data["line1"],
      root["line1"],
    ]) ?? "Mithka"
    let senderName = Self.firstNonEmpty([
      locArgs.first,
      data["line1"],
      root["line1"],
      fallbackTitle,
    ]) ?? fallbackTitle
    let groupTitle = chat.groupConversation
      ? Self.firstNonEmpty([
          locArgs.count > 2 ? locArgs[1] : nil,
          content.title,
          data["title"],
          root["title"],
        ]) ?? fallbackTitle
      : fallbackTitle
    let body = Self.firstNonEmpty([
      content.body,
      data["line2"],
      root["line2"],
      data["text"],
      root["text"],
    ]) ?? ""
    let accountId = Self.int64(data["user_id"] ?? root["user_id"])
    let conversationIdentifier = accountId == nil
      ? "telegram:\(chat.chatId)"
      : "telegram:\(accountId!):\(chat.chatId)"

    information = CommunicationNotificationInformation(
      title: groupTitle,
      body: body,
      conversationIdentifier: conversationIdentifier,
      senderName: senderName,
      groupConversation: chat.groupConversation,
      avatarData: NotificationAvatarStore.avatarData(chatId: chat.chatId)
    )
  }

  private static func chatIdentity(
    from custom: [String: Any]
  ) -> (chatId: Int64, groupConversation: Bool)? {
    if let id = int64(custom["encryption_id"]), id > 0 {
      return (-2_000_000_000_000 + id, false)
    }
    if let id = int64(custom["channel_id"]), id > 0 {
      return (-1_000_000_000_000 - id, true)
    }
    if let id = int64(custom["chat_id"]), id > 0 {
      return (-id, true)
    }
    if let id = int64(custom["from_id"]), id > 0 {
      return (id, false)
    }
    return nil
  }

  private static func stringKeyed(_ value: [AnyHashable: Any]) -> [String: Any] {
    Dictionary(uniqueKeysWithValues: value.map { (String(describing: $0.key), $0.value) })
  }

  private static func dictionary(_ value: Any?) -> [String: Any]? {
    if let value = value as? [String: Any] { return value }
    if let value = value as? [AnyHashable: Any] { return stringKeyed(value) }
    if let value = value as? String,
       let data = value.data(using: .utf8),
       let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    {
      return decoded
    }
    return nil
  }

  private static func stringArray(_ value: Any?) -> [String] {
    (value as? [Any] ?? []).map { String(describing: $0) }
  }

  private static func int64(_ value: Any?) -> Int64? {
    if let value = value as? NSNumber { return value.int64Value }
    if let value = value as? String { return Int64(value) }
    return nil
  }

  private static func firstNonEmpty(_ values: [Any?]) -> String? {
    for value in values {
      let text = value.map {
        String(describing: $0).trimmingCharacters(in: .whitespacesAndNewlines)
      }
      if let text, !text.isEmpty { return text }
    }
    return nil
  }
}
