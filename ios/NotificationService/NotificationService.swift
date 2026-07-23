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

  override func serviceExtensionTimeWillExpire() {
    finish(with: bestAttemptContent)
  }

  private func finish(with content: UNNotificationContent?) {
    guard let handler = contentHandler else { return }
    contentHandler = nil
    handler(content ?? bestAttemptContent ?? UNNotificationContent())
  }
}
