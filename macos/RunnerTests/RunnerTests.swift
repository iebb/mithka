import Cocoa
import FlutterMacOS
import XCTest
@testable import Mithka

class RunnerTests: XCTestCase {
  func testNativeTestHostDetectionDoesNotDependOnOneXCTestSignal() {
    XCTAssertTrue(
      MainFlutterWindow.isNativeTestHost(
        environment: [
          "XCTestConfigurationFilePath": "/tmp/RunnerTests.xctestconfiguration"
        ],
        isXCTestLoaded: false
      )
    )
    XCTAssertTrue(
      MainFlutterWindow.isNativeTestHost(
        environment: [:],
        isXCTestLoaded: true
      )
    )
    XCTAssertFalse(
      MainFlutterWindow.isNativeTestHost(
        environment: [:],
        isXCTestLoaded: false
      )
    )
  }

  @MainActor
  func testMainWindowCloseHidesWithoutDestroyingWindow() {
    let window = makeMainWindow()
    window.orderFront(nil)

    window.close()

    XCTAssertFalse(window.isVisible)
    XCTAssertFalse(window.isReleasedWhenClosed)
    XCTAssertNotNil(window.contentViewController)
  }

  @MainActor
  func testMainWindowMinimizeHidesInsteadOfCreatingDockThumbnail() {
    let window = makeMainWindow()
    window.orderFront(nil)

    window.miniaturize(nil)

    XCTAssertFalse(window.isVisible)
    XCTAssertFalse(window.isMiniaturized)
    XCTAssertNotNil(window.contentViewController)
  }

  @MainActor
  func testDockReopenRestoresTheRetainedPrimaryWindow() throws {
    let delegate = try XCTUnwrap(NSApp.delegate as? AppDelegate)
    let window = try XCTUnwrap(delegate.mainFlutterWindow as? MainFlutterWindow)
    window.close()
    XCTAssertFalse(window.isVisible)

    let shouldRunDefaultReopen = delegate.applicationShouldHandleReopen(
      NSApp,
      hasVisibleWindows: false
    )

    XCTAssertFalse(shouldRunDefaultReopen)
    XCTAssertTrue(window.isVisible)
  }

  @MainActor
  func testStatusItemShowRestoresTheRetainedPrimaryWindow() throws {
    let delegate = try XCTUnwrap(NSApp.delegate as? AppDelegate)
    let window = try XCTUnwrap(delegate.mainFlutterWindow as? MainFlutterWindow)
    window.close()
    XCTAssertFalse(window.isVisible)

    let showMainWindow = NSSelectorFromString("showMainWindow")
    XCTAssertTrue(delegate.responds(to: showMainWindow))
    _ = delegate.perform(showMainWindow)

    XCTAssertTrue(window.isVisible)
  }

  @MainActor
  func testTerminationBridgePinsThePrimaryEngineAndIsIdempotent() {
    let bridge = ApplicationTerminationBridge(timeoutSeconds: 1)
    let primary = NSObject()
    let child = NSObject()
    var primaryInvocationCount = 0
    var primaryResult: FlutterResult?
    var childWasInvoked = false

    XCTAssertTrue(
      bridge.bindPrimary(owner: primary) { result in
        primaryInvocationCount += 1
        primaryResult = result
      }
    )
    XCTAssertFalse(
      bridge.bindPrimary(owner: child) { _ in
        childWasInvoked = true
      }
    )
    XCTAssertFalse(bridge.acknowledgeReady(from: child))
    XCTAssertTrue(bridge.acknowledgeReady(from: primary))

    var replies: [Bool] = []
    XCTAssertEqual(
      bridge.requestTermination { replies.append($0) },
      .terminateLater
    )
    XCTAssertEqual(
      bridge.requestTermination { _ in
        XCTFail("A duplicate Quit request must share the pending reply")
      },
      .terminateLater
    )
    XCTAssertEqual(primaryInvocationCount, 1)
    XCTAssertFalse(childWasInvoked)

    primaryResult?(true)
    XCTAssertEqual(replies, [true])
    XCTAssertEqual(bridge.requestTermination { _ in }, .terminateNow)
  }

  @MainActor
  func testTerminationBridgeExitsBeforeReadyAndCancelsWhenTimedOut() {
    let bridge = ApplicationTerminationBridge(timeoutSeconds: 0.02)
    let primary = NSObject()
    var invocationCount = 0
    var results: [FlutterResult] = []

    XCTAssertEqual(
      bridge.requestTermination { _ in
        XCTFail("An unbound bridge must not reply asynchronously")
      },
      .terminateNow
    )
    XCTAssertTrue(
      bridge.bindPrimary(owner: primary) { result in
        invocationCount += 1
        results.append(result)
      }
    )
    XCTAssertEqual(
      bridge.requestTermination { _ in
        XCTFail("A bridge without Dart's ready acknowledgement replies inline")
      },
      .terminateNow
    )
    XCTAssertTrue(bridge.acknowledgeReady(from: primary))

    let timedOut = expectation(description: "termination timeout replies false")
    XCTAssertEqual(
      bridge.requestTermination { allowed in
        XCTAssertFalse(allowed)
        timedOut.fulfill()
      },
      .terminateLater
    )
    wait(for: [timedOut], timeout: 1)
    XCTAssertEqual(invocationCount, 1)

    var retryReplies: [Bool] = []
    XCTAssertEqual(
      bridge.requestTermination { retryReplies.append($0) },
      .terminateLater
    )
    XCTAssertEqual(invocationCount, 2)

    // A callback from the timed-out attempt must never approve or complete a
    // newer Quit request.
    results[0](true)
    XCTAssertTrue(retryReplies.isEmpty)
    results[1](true)
    XCTAssertEqual(retryReplies, [true])
  }

  @MainActor
  private func makeMainWindow() -> MainFlutterWindow {
    let window = MainFlutterWindow(
      contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
      styleMask: [.titled, .closable, .miniaturizable],
      backing: .buffered,
      defer: false
    )
    window.contentViewController = NSViewController()
    window.isReleasedWhenClosed = false
    addTeardownBlock { @MainActor in
      window.orderOut(nil)
    }
    return window
  }
}
