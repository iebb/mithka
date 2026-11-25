import UIKit
import UniformTypeIdentifiers
import UserNotifications

/// "Open in Mithka" in the share sheet.
///
/// Takes the one shared URL, keeps it only if it is a Telegram link (see
/// `TelegramShareLink.normalized`), and hands it to Mithka as
/// `mk://open?url=<link>`. The link is first saved, silently, in the App
/// Group (Mithka opens it when it next becomes active), then:
/// 1. Opened directly, through the `UIApplication` found on the responder
///    chain once the view is in a window. Stays transparent while it tries,
///    so the sheet barely shows. Success takes the saved copy back.
/// 2. If that is unavailable, refused or never answers: posts a notification
///    whose tap opens the saved link, and says so.
final class ActionViewController: UIViewController {
  private enum Phase {
    case loading, opening, fallback, finished
  }

  /// How long the direct open may take before the fallback runs.
  private static let openTimeout: TimeInterval = 1.5
  private static let refusalDuration: TimeInterval = 1.8
  /// Longer shared input is refused as not a Telegram link.
  private static let maxInputBytes = 4096

  private var phase = Phase.loading
  /// The App Group entry for this request's link, written once before the
  /// direct open; [saved] is whether that write succeeded.
  private var savedID: String?
  private var saved = false
  private var appeared = false
  /// A link waiting for the view to reach a window, so the responder chain
  /// is complete before the direct open walks it.
  private var waitingToOpen: URL?

  override func loadView() {
    view = UIView()
    view.backgroundColor = .clear
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    preferredContentSize = CGSize(width: 1, height: 1)
    // The host going away while the direct open runs means Mithka took over.
    for name in [Notification.Name.NSExtensionHostWillResignActive, .NSExtensionHostDidEnterBackground] {
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(hostLeft),
        name: name,
        object: nil
      )
    }
    Task { @MainActor in
      let raw = await Self.sharedURLString(in: extensionContext)
      guard
        let raw,
        let link = TelegramShareLink.normalized(raw),
        let url = TelegramShareLink.mithkaOpenLink(for: link)
      else {
        showRefusal()
        return
      }
      if appeared, view.window != nil {
        open(url)
      } else {
        waitingToOpen = url
      }
    }
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    appeared = true
    if let url = waitingToOpen {
      waitingToOpen = nil
      open(url)
    }
  }

  // MARK: - Input

  private static func sharedURLString(in context: NSExtensionContext?) async -> String? {
    let items = context?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
    let providers = items.flatMap { $0.attachments ?? [] }
    let urlType = UTType.url.identifier
    guard
      let provider = providers.first(where: {
        $0.hasItemConformingToTypeIdentifier(urlType)
          && !$0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
      })
    else { return nil }
    let limit = maxInputBytes
    return await withCheckedContinuation { continuation in
      provider.loadItem(forTypeIdentifier: urlType, options: nil) { item, _ in
        let string: String?
        switch item {
        case let url as URL: string = url.absoluteString
        case let data as Data:
          string = URL(dataRepresentation: data, relativeTo: nil)?.absoluteString
            ?? String(data: data, encoding: .utf8)
        case let text as String: string = text
        default: string = nil
        }
        let bounded = string.flatMap { $0.utf8.count <= limit ? $0 : nil }
        continuation.resume(returning: bounded)
      }
    }
  }

  // MARK: - Direct open

  private func open(_ url: URL) {
    phase = .opening
    // If the host leaves for something other than Mithka (a call, the lock
    // screen) and the open then fails or never answers, this copy is what
    // still gets the link to Mithka.
    _ = save(url)
    guard let application = hostApplication() else {
      runFallback(url)
      return
    }
    application.open(url, options: [:]) { [weak self] opened in
      Task { @MainActor in self?.openFinished(opened, url: url) }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.openTimeout) { [weak self] in
      guard let self, self.phase == .opening else { return }
      self.runFallback(url)
    }
  }

  /// The app's `UIApplication`, reached through `UIResponder.next`. Public
  /// symbols only; nil when the chain does not lead there.
  private func hostApplication() -> UIApplication? {
    var responder: UIResponder? = self
    while let current = responder {
      if let application = current as? UIApplication { return application }
      responder = current.next
    }
    return nil
  }

  /// Ends the request once the host leaves after the direct open started.
  /// The host may have left for Mithka or for something else, so the saved
  /// entry stays: Mithka drops it as a repeat of the URL it just got, or
  /// opens it when it next becomes active. The timeout then finds the phase
  /// changed and skips the fallback.
  @objc private func hostLeft() {
    guard phase == .opening else { return }
    finish()
  }

  private func openFinished(_ opened: Bool, url: URL) {
    if opened {
      // Mithka has the link by URL, whatever happened meanwhile: take back
      // the saved copy and any notification so it does not open twice.
      withdrawSaved()
      if phase != .finished { finish() }
    } else if phase == .opening {
      runFallback(url)
    }
  }

  /// Saves [url] in the App Group the first time; later calls reuse that
  /// entry. Returns its ID.
  private func save(_ url: URL) -> String {
    if let savedID { return savedID }
    let id = UUID().uuidString
    savedID = id
    saved = SharedLinkQueue.shared?.enqueue(id: id, link: url.absoluteString) ?? false
    return id
  }

  private func withdrawSaved() {
    guard let id = savedID else { return }
    if saved { _ = SharedLinkQueue.shared?.claim(id: id) }
    let center = UNUserNotificationCenter.current()
    center.removePendingNotificationRequests(withIdentifiers: [id])
    center.removeDeliveredNotifications(withIdentifiers: [id])
  }

  // MARK: - Fallback

  private func runFallback(_ url: URL) {
    phase = .fallback
    let id = save(url)
    let link = url.absoluteString
    let queued = saved
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      let allowed: Bool
      switch settings.authorizationStatus {
      case .authorized, .provisional, .ephemeral: allowed = settings.alertSetting != .disabled
      default: allowed = false
      }
      Task { @MainActor in
        // A late direct open may have finished the request meanwhile.
        guard self.phase == .fallback else { return }
        if allowed {
          self.postNotification(id: id, link: link, queued: queued)
        } else {
          self.showFallback(notificationPosted: false, queued: queued)
        }
      }
    }
  }

  private func postNotification(id: String, link: String, queued: Bool) {
    let content = UNMutableNotificationContent()
    content.title = Copy.notificationTitle
    content.body = Copy.notificationBody
    content.sound = nil
    content.threadIdentifier = "open-in-mithka"
    content.userInfo = [
      SharedLinkQueue.UserInfoKey.link: link,
      SharedLinkQueue.UserInfoKey.id: id,
      SharedLinkQueue.UserInfoKey.queued: queued,
    ]
    let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
    let center = UNUserNotificationCenter.current()
    center.add(request) { error in
      Task { @MainActor in
        guard self.phase == .fallback else {
          // Finished by a late direct open while this was being added.
          center.removePendingNotificationRequests(withIdentifiers: [id])
          center.removeDeliveredNotifications(withIdentifiers: [id])
          return
        }
        self.showFallback(notificationPosted: error == nil, queued: queued)
      }
    }
  }

  /// Says only what actually happened: a notification to tap, a saved link
  /// that opens with Mithka, or — when neither worked — that it failed.
  private func showFallback(notificationPosted: Bool, queued: Bool) {
    guard phase == .fallback else { return }
    let card: Card
    if notificationPosted {
      card = Card(title: Copy.continueTitle, message: Copy.tapNotification)
    } else if queued {
      card = Card(title: Copy.continueTitle, message: Copy.opensNextTime)
    } else {
      card = Card(title: nil, message: Copy.openFailed)
    }
    card.addDoneButton(title: Copy.done) { [weak self] in self?.finish() }
    present(card)
  }

  // MARK: - Refusal

  private func showRefusal() {
    phase = .finished
    present(Card(title: nil, message: Copy.notTelegramLink))
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.refusalDuration) { [weak self] in
      self?.extensionContext?.completeRequest(returningItems: nil)
    }
  }

  private func finish() {
    phase = .finished
    extensionContext?.completeRequest(returningItems: nil)
  }

  private func present(_ card: Card) {
    preferredContentSize = CGSize(width: 320, height: 160)
    view.backgroundColor = UIColor.black.withAlphaComponent(0.2)
    card.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(card)
    NSLayoutConstraint.activate([
      card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      card.widthAnchor.constraint(lessThanOrEqualToConstant: 320),
      card.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
      card.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
    ])
  }
}

/// Copy shown by the extension. Every key lives in the extension's
/// Localizable.strings; `value` is the English fallback for a locale whose
/// table does not have the key yet.
private enum Copy {
  static var notTelegramLink: String {
    text("linkNotTelegramLink", "Only Telegram links can be opened in Mithka.")
  }
  static var openFailed: String {
    text("linkHandlerOpenTelegramLinkFailed", "Unable to open Telegram link")
  }
  static var continueTitle: String { text("linkShareContinueTitle", "Open Mithka to continue") }
  static var tapNotification: String {
    text("linkShareTapNotification", "Tap the notification to open the link in Mithka.")
  }
  static var opensNextTime: String {
    text("linkShareOpensNextTime", "The link will open the next time you open Mithka.")
  }
  static var notificationTitle: String {
    text("linkShareNotificationTitle", "Your Telegram link is ready")
  }
  static var notificationBody: String {
    text("linkShareNotificationBody", "Tap to open it in Mithka.")
  }
  static var done: String { text("linkShareDone", "Done") }

  private static func text(_ key: String, _ english: String) -> String {
    NSLocalizedString(key, tableName: nil, bundle: .main, value: english, comment: "")
  }
}

/// A 14pt-radius blurred card: optional 17pt semibold title, 15pt message,
/// optional 17pt Done button; 20pt padding, 12pt spacing.
private final class Card: UIVisualEffectView {
  private let stack = UIStackView()

  init(title: String?, message: String) {
    super.init(effect: UIBlurEffect(style: .systemThickMaterial))
    layer.cornerRadius = 14
    clipsToBounds = true
    stack.axis = .vertical
    stack.alignment = .center
    stack.spacing = 12
    stack.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
      stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
      stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
      stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
    ])
    if let title {
      stack.addArrangedSubview(label(title, font: .systemFont(ofSize: 17, weight: .semibold)))
    }
    stack.addArrangedSubview(label(message, font: .systemFont(ofSize: 15)))
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  func addDoneButton(title: String, action: @escaping () -> Void) {
    let button = UIButton(type: .system)
    button.setTitle(title, for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
    button.addAction(UIAction { _ in action() }, for: .touchUpInside)
    stack.addArrangedSubview(button)
  }

  private func label(_ text: String, font: UIFont) -> UILabel {
    let label = UILabel()
    label.text = text
    label.font = font
    label.textColor = .label
    label.numberOfLines = 0
    label.textAlignment = .center
    return label
  }
}
