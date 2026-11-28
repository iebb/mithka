import Foundation

/// Telegram links the "Open in Mithka" action could not hand to Mithka
/// directly. Compiled into both Runner and the OpenInMithka extension; they
/// share it through the App Group both already belong to.
///
/// One file per entry under `<group>/OpenInMithka/Pending`. Writes land with
/// an atomic rename from `Staging`, and every read takes its entry with an
/// atomic rename into `Claimed` first, so the extension and Mithka never see
/// a half-written entry and only one of them gets each one: whichever comes
/// first — Mithka becoming active (`drain`) or a tap on the extension's
/// notification (`claim`) — opens it, and the other finds nothing.
struct SharedLinkQueue {
  static let appGroup = "group.ad.neko.mithka.notifications"

  /// Notification userInfo keys. The link itself is never shown in the
  /// notification text, only carried here.
  enum UserInfoKey {
    static let link = "mithkaSharedLink"
    static let id = "mithkaSharedLinkID"
    static let queued = "mithkaSharedLinkQueued"
  }

  /// Entries older than this are dropped unopened.
  static let maxAge: TimeInterval = 7 * 24 * 60 * 60
  /// Staging and Claimed files older than this were left by a process that
  /// died between its two steps.
  static let orphanAge: TimeInterval = 10 * 60

  /// The queue in the App Group container; nil when the group is unavailable.
  static var shared: SharedLinkQueue? {
    FileManager.default
      .containerURL(forSecurityApplicationGroupIdentifier: appGroup)
      .map { SharedLinkQueue(directory: $0.appendingPathComponent("OpenInMithka", isDirectory: true)) }
  }

  let directory: URL

  private var pending: URL { directory.appendingPathComponent("Pending", isDirectory: true) }
  private var staging: URL { directory.appendingPathComponent("Staging", isDirectory: true) }
  private var claimed: URL { directory.appendingPathComponent("Claimed", isDirectory: true) }
  private static let suffix = "link"

  /// Stores [link] under [id] (a UUID string). False when it could not be
  /// written.
  @discardableResult
  func enqueue(id: String, link: String, now: Date = Date()) -> Bool {
    guard UUID(uuidString: id) != nil else { return false }
    let fileManager = FileManager.default
    let temporary = staging.appendingPathComponent("\(UUID().uuidString).tmp")
    do {
      try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
      try fileManager.createDirectory(at: pending, withIntermediateDirectories: true)
      let data = try JSONSerialization.data(
        withJSONObject: ["link": link, "created": now.timeIntervalSince1970]
      )
      try data.write(to: temporary)
      try fileManager.moveItem(at: temporary, to: entryURL(id))
      return true
    } catch {
      try? fileManager.removeItem(at: temporary)
      return false
    }
  }

  /// Takes the entry [id] and returns its link, or nil when it was already
  /// drained or claimed, or has expired.
  func claim(id: String, now: Date = Date()) -> String? {
    guard UUID(uuidString: id) != nil else { return nil }
    return take(entryURL(id), now: now)?.link
  }

  /// Takes every entry and returns the links still fresh, oldest first.
  func drain(now: Date = Date()) -> [String] {
    drainEntries(now: now).links
  }

  /// Takes every entry: [links] are the fresh ones, oldest first; [ids] are
  /// all entries taken, expired ones included, so their notifications can
  /// go too.
  func drainEntries(now: Date = Date()) -> (links: [String], ids: [String]) {
    removeOrphans(in: staging, now: now)
    removeOrphans(in: claimed, now: now)
    let files = (try? FileManager.default.contentsOfDirectory(
      at: pending,
      includingPropertiesForKeys: nil
    )) ?? []
    let taken = files
      .filter { $0.pathExtension == Self.suffix }
      .compactMap { file in
        take(file, now: now, keepExpired: true).map {
          (id: file.deletingPathExtension().lastPathComponent, entry: $0)
        }
      }
    let links = taken
      .filter { $0.entry.created >= now.timeIntervalSince1970 - Self.maxAge }
      .sorted { $0.entry.created < $1.entry.created }
      .map(\.entry.link)
    return (links, taken.map(\.id))
  }

  private func entryURL(_ id: String) -> URL {
    pending.appendingPathComponent(id).appendingPathExtension(Self.suffix)
  }

  private func removeOrphans(in folder: URL, now: Date) {
    let fileManager = FileManager.default
    let files = (try? fileManager.contentsOfDirectory(
      at: folder,
      includingPropertiesForKeys: [.contentModificationDateKey]
    )) ?? []
    for file in files {
      let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
        .contentModificationDate ?? .distantPast
      if now.timeIntervalSince(modified) > Self.orphanAge {
        try? fileManager.removeItem(at: file)
      }
    }
  }

  /// Moves [file] out of Pending (only one caller can win the rename), then
  /// reads and deletes it. Expired entries count as taken but yield nil
  /// unless [keepExpired].
  private func take(
    _ file: URL,
    now: Date,
    keepExpired: Bool = false
  ) -> (link: String, created: TimeInterval)? {
    let fileManager = FileManager.default
    let mine = claimed.appendingPathComponent("\(UUID().uuidString).\(Self.suffix)")
    do {
      try fileManager.createDirectory(at: claimed, withIntermediateDirectories: true)
      try fileManager.moveItem(at: file, to: mine)
    } catch {
      return nil
    }
    defer { try? fileManager.removeItem(at: mine) }
    guard
      let data = try? Data(contentsOf: mine),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let link = object["link"] as? String,
      let created = object["created"] as? Double,
      keepExpired || created >= now.timeIntervalSince1970 - Self.maxAge
    else { return nil }
    return (link, created)
  }
}

/// The share action's side of `normalizeTelegramLink`, `unwrapMithkaOpenLink`
/// and `mithkaOpenLinkFor` (lib/chat/links_search/telegram_link.dart). Web
/// links are stricter here: http(s) only and no userinfo (so `mailto:a@t.me`
/// is not read as host t.me), where Dart takes both.
enum TelegramShareLink {
  static let webHosts: Set<String> = [
    "t.me", "www.t.me", "telegram.me", "www.telegram.me", "telegram.dog", "www.telegram.dog",
  ]

  /// The Telegram link in [raw] (tg:, Mithka's mk: and mithka: as tg: with
  /// `open?url=` wrappers unwrapped, or http(s) on [webHosts] as https), or
  /// nil for anything else.
  static func normalized(_ raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let lower = trimmed.lowercased()
    if lower.hasPrefix("tg:") { return trimmed }
    for scheme in ["mk:", "mithka:"] where lower.hasPrefix(scheme) {
      if let wrapped = URLComponents(string: trimmed),
         wrapped.host?.lowercased() == openHost,
         let inner = unwrapped(wrapped) {
        return inner
      }
      return "tg:\(trimmed.dropFirst(scheme.count))"
    }
    let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
    guard
      var components = URLComponents(string: candidate),
      let scheme = components.scheme?.lowercased(),
      scheme == "https" || scheme == "http",
      components.user == nil,
      components.password == nil,
      let host = components.host?.lowercased(),
      webHosts.contains(host)
    else { return nil }
    components.scheme = "https"
    components.host = host
    return components.string
  }

  /// `mk://open?url=<percent-encoded link>`; every character outside
  /// RFC 3986's unreserved set is encoded so `&`, `=` and `+` survive.
  static func mithkaOpenLink(for link: String) -> URL? {
    let encoded = link.addingPercentEncoding(withAllowedCharacters: unreserved)
    return encoded.flatMap { URL(string: "mk://open?url=\($0)") }
  }

  private static let openHost = "open"

  /// The normalized Telegram link inside an `open?url=` wrapper; wrappers
  /// never nest.
  private static func unwrapped(_ wrapper: URLComponents) -> String? {
    guard
      let inner = wrapper.queryItems?.last(where: { $0.name == "url" })?.value?
        .trimmingCharacters(in: .whitespacesAndNewlines),
      !inner.isEmpty
    else { return nil }
    let lower = inner.lowercased()
    if lower.hasPrefix("mk:") || lower.hasPrefix("mithka:") { return nil }
    return normalized(inner)
  }

  /// Whether [link] is a wrapper built by [mithkaOpenLink].
  static func isMithkaOpenLink(_ link: String) -> Bool {
    link.hasPrefix("mk://open?url=")
  }

  private static let unreserved = CharacterSet(
    charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
  )
}
