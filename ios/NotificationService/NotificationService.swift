import Intents
import UIKit
import UserNotifications

final class NotificationService: UNNotificationServiceExtension {
  private var contentHandler: ((UNNotificationContent) -> Void)?
  private var bestAttemptContent: UNMutableNotificationContent?

  override func didReceive(
    _ request: UNNotificationRequest,
    withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
  ) {
    self.contentHandler = contentHandler
    guard
      let mutableContent = request.content.mutableCopy() as? UNMutableNotificationContent
    else {
      contentHandler(request.content)
      return
    }
    // Stamp the account before anything else can return early. A tap reads
    // back whatever userInfo was delivered, and the app's own account registry
    // is empty when a tap is what started it — so this is the only moment the
    // slot is both known and attachable.
    Self.stampAccountSlot(on: mutableContent)
    bestAttemptContent = mutableContent

    guard
      #available(iOSApplicationExtension 15.0, *),
      let remote = RemoteCommunicationNotification(
        content: mutableContent,
        userInfo: mutableContent.userInfo
      )
    else {
      finish(with: mutableContent)
      return
    }

    Task {
      do {
        let enriched = try await remote.information.enrichedContent(from: mutableContent)
        finish(with: enriched)
      } catch {
        finish(with: mutableContent)
      }
    }
  }

  /// Writes the account slot into `userInfo` when the payload names its
  /// account and that account is signed in.
  ///
  /// Telegram carries the account as a user id; the slot is looked up from the
  /// map the app shares through the app group. A payload naming no account, or
  /// one no longer signed in, is left alone — a wrong slot would be worse than
  /// none, since it would point navigation at the wrong conversation.
  private static func stampAccountSlot(on content: UNMutableNotificationContent) {
    var userInfo = content.userInfo
    let root = stringKeyed(userInfo)
    let data = dictionary(root["data"]) ?? root
    guard
      let userId = int64(data["user_id"] ?? root["user_id"]),
      let slot = NotificationAccountStore.slot(forUserId: userId)
    else {
      return
    }
    userInfo[accountSlotUserInfoKey] = slot
    userInfo[accountUserIdUserInfoKey] = "\(userId)"
    content.userInfo = userInfo
  }

  private static func stringKeyed(_ value: [AnyHashable: Any]) -> [String: Any] {
    var result: [String: Any] = [:]
    for (key, item) in value {
      result["\(key)"] = item
    }
    return result
  }

  private static func dictionary(_ value: Any?) -> [String: Any]? {
    if let map = value as? [String: Any] { return map }
    if let map = value as? [AnyHashable: Any] { return stringKeyed(map) }
    if
      let text = value as? String,
      let data = text.data(using: .utf8),
      let decoded = try? JSONSerialization.jsonObject(with: data)
    {
      return dictionary(decoded)
    }
    return nil
  }

  private static func int64(_ value: Any?) -> Int64? {
    if let number = value as? Int64 { return number }
    if let number = value as? Int { return Int64(number) }
    if let number = value as? NSNumber { return number.int64Value }
    if let text = value as? String { return Int64(text) }
    return nil
  }

  override func serviceExtensionTimeWillExpire() {
    finish(with: bestAttemptContent)
  }

  private func finish(with content: UNNotificationContent?) {
    guard let handler = contentHandler else { return }
    contentHandler = nil
    handler(content ?? bestAttemptContent ?? UNNotificationContent())
  }
}
