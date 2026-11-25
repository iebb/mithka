import XCTest
@testable import Runner

/// SharedLinkQueue is compiled into Runner and the OpenInMithka extension;
/// these run it against a temporary directory instead of the App Group.
final class SharedLinkQueueTests: XCTestCase {
  private var directory: URL!
  private var queue: SharedLinkQueue!
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("SharedLinkQueueTests-\(UUID().uuidString)", isDirectory: true)
    queue = SharedLinkQueue(directory: directory)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
  }

  func testDrainReturnsEveryLinkOnceOldestFirst() {
    let first = UUID().uuidString
    let second = UUID().uuidString
    XCTAssertTrue(queue.enqueue(id: second, link: "mk://open?url=b", now: now))
    XCTAssertTrue(queue.enqueue(id: first, link: "mk://open?url=a", now: now - 60))

    XCTAssertEqual(queue.drain(now: now), ["mk://open?url=a", "mk://open?url=b"])
    XCTAssertEqual(queue.drain(now: now), [])
  }

  func testClaimTakesOnlyItsEntryAndOnlyOnce() {
    let tapped = UUID().uuidString
    let other = UUID().uuidString
    queue.enqueue(id: tapped, link: "mk://open?url=tapped", now: now)
    queue.enqueue(id: other, link: "mk://open?url=other", now: now)

    XCTAssertEqual(queue.claim(id: tapped, now: now), "mk://open?url=tapped")
    XCTAssertNil(queue.claim(id: tapped, now: now))
    XCTAssertEqual(queue.drain(now: now), ["mk://open?url=other"])
  }

  func testTapAfterDrainOpensNothing() {
    let id = UUID().uuidString
    queue.enqueue(id: id, link: "mk://open?url=a", now: now)

    XCTAssertEqual(queue.drain(now: now), ["mk://open?url=a"])
    XCTAssertNil(queue.claim(id: id, now: now))
  }

  func testExpiredEntriesAreDroppedByDrainAndClaim() {
    let old = now - SharedLinkQueue.maxAge - 1
    let drained = UUID().uuidString
    let claimed = UUID().uuidString
    queue.enqueue(id: drained, link: "mk://open?url=drained", now: old)
    queue.enqueue(id: claimed, link: "mk://open?url=claimed", now: old)

    XCTAssertNil(queue.claim(id: claimed, now: now))
    XCTAssertEqual(queue.drain(now: now), [])
    XCTAssertEqual(queue.drain(now: now), [], "expired entries are removed, not kept")
  }

  func testMalformedEntriesAreDroppedNotReturned() throws {
    let pending = directory.appendingPathComponent("Pending", isDirectory: true)
    try FileManager.default.createDirectory(at: pending, withIntermediateDirectories: true)
    for (index, body) in ["not json", #"{"link": 1, "created": 0}"#, #"["mk://open?url=a"]"#].enumerated() {
      let id = UUID().uuidString
      try Data(body.utf8).write(to: pending.appendingPathComponent("\(id).link"))
      if index == 0 { XCTAssertNil(queue.claim(id: id, now: now)) }
    }
    let good = UUID().uuidString
    queue.enqueue(id: good, link: "mk://open?url=good", now: now)

    XCTAssertEqual(queue.drain(now: now), ["mk://open?url=good"])
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: pending.path), [])
  }

  func testDrainEntriesReportsEveryTakenIdIncludingExpired() {
    let fresh = UUID().uuidString
    let expired = UUID().uuidString
    queue.enqueue(id: fresh, link: "mk://open?url=fresh", now: now)
    queue.enqueue(id: expired, link: "mk://open?url=expired", now: now - SharedLinkQueue.maxAge - 1)

    let drained = queue.drainEntries(now: now)
    XCTAssertEqual(drained.links, ["mk://open?url=fresh"])
    XCTAssertEqual(Set(drained.ids), [fresh, expired])
  }

  func testDrainRemovesOnlyStaleStagingAndClaimedFiles() throws {
    let fileManager = FileManager.default
    var files: [(URL, stale: Bool)] = []
    for folder in ["Staging", "Claimed"] {
      let url = directory.appendingPathComponent(folder, isDirectory: true)
      try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
      for stale in [true, false] {
        let file = url.appendingPathComponent("\(UUID().uuidString).tmp")
        try Data("{}".utf8).write(to: file)
        let age = stale ? SharedLinkQueue.orphanAge + 1 : 60
        try fileManager.setAttributes([.modificationDate: now - age], ofItemAtPath: file.path)
        files.append((file, stale))
      }
    }

    _ = queue.drain(now: now)
    for (file, stale) in files {
      XCTAssertEqual(fileManager.fileExists(atPath: file.path), !stale, file.lastPathComponent)
    }
  }

  func testRejectsIdsThatAreNotUUIDs() {
    XCTAssertFalse(queue.enqueue(id: "../escape", link: "mk://open?url=a", now: now))
    XCTAssertNil(queue.claim(id: "../escape", now: now))
  }

  func testConcurrentDrainsHandOutEachEntryOnce() {
    let ids = (0..<40).map { _ in UUID().uuidString }
    for (index, id) in ids.enumerated() {
      queue.enqueue(id: id, link: "mk://open?url=\(index)", now: now)
    }
    let lock = NSLock()
    var taken: [String] = []
    DispatchQueue.concurrentPerform(iterations: 8) { iteration in
      let links = iteration.isMultiple(of: 2)
        ? queue.drain(now: now)
        : ids.compactMap { queue.claim(id: $0, now: now) }
      lock.lock()
      taken += links
      lock.unlock()
    }
    XCTAssertEqual(taken.count, ids.count)
    XCTAssertEqual(Set(taken).count, ids.count)
  }

  func testNormalizesOnlyTelegramLinks() {
    XCTAssertEqual(
      TelegramShareLink.normalized(" tg://resolve?domain=durov "),
      "tg://resolve?domain=durov"
    )
    XCTAssertEqual(TelegramShareLink.normalized("http://t.me/durov"), "https://t.me/durov")
    XCTAssertEqual(TelegramShareLink.normalized("https://WWW.Telegram.Me/x"), "https://www.telegram.me/x")
    XCTAssertEqual(TelegramShareLink.normalized("telegram.dog/x"), "https://telegram.dog/x")
    XCTAssertNil(TelegramShareLink.normalized("https://apple.com"))
    XCTAssertNil(TelegramShareLink.normalized("https://t.me.example.com/x"))
    XCTAssertNil(TelegramShareLink.normalized("ftp://t.me/x"))
    XCTAssertNil(TelegramShareLink.normalized("mailto:a@t.me"))
    XCTAssertNil(TelegramShareLink.normalized("https://user:pass@t.me/x"))
    XCTAssertNil(TelegramShareLink.normalized(""))
  }

  /// Mithka's own schemes follow normalizeTelegramLink
  /// (lib/chat/links_search/telegram_link.dart).
  func testNormalizesMithkaLinksLikeDart() {
    XCTAssertEqual(
      TelegramShareLink.normalized("mk://resolve?domain=durov"),
      "tg://resolve?domain=durov"
    )
    XCTAssertEqual(
      TelegramShareLink.normalized("mithka://resolve?domain=durov"),
      "tg://resolve?domain=durov"
    )
    XCTAssertEqual(
      TelegramShareLink.normalized("mk://open?url=https%3A%2F%2Ft.me%2Fdurov"),
      "https://t.me/durov"
    )
    XCTAssertEqual(
      TelegramShareLink.normalized("MITHKA://open?url=tg%3A%2F%2Fresolve%3Fdomain%3Dx"),
      "tg://resolve?domain=x"
    )
    // A wrapper that does not unwrap falls back to the plain tg: grammar, and
    // wrappers never nest.
    XCTAssertEqual(
      TelegramShareLink.normalized("mk://open?url=mk%3A%2F%2Fopen%3Furl%3Dx"),
      "tg://open?url=mk%3A%2F%2Fopen%3Furl%3Dx"
    )
  }

  func testWrapsLinksForMithkaWithEverySeparatorEncoded() throws {
    let url = try XCTUnwrap(
      TelegramShareLink.mithkaOpenLink(for: "https://t.me/x?start=a&b=c+d é")
    )
    XCTAssertEqual(
      url.absoluteString,
      "mk://open?url=https%3A%2F%2Ft.me%2Fx%3Fstart%3Da%26b%3Dc%2Bd%20%C3%A9"
    )
    let item = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first
    XCTAssertEqual(item?.name, "url")
    XCTAssertEqual(item?.value, "https://t.me/x?start=a&b=c+d é")
    XCTAssertTrue(TelegramShareLink.isMithkaOpenLink(url.absoluteString))
    XCTAssertFalse(TelegramShareLink.isMithkaOpenLink("tg://resolve?domain=durov"))
  }
}
