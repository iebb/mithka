import Cocoa
import FlutterMacOS
import XCTest

@testable import Mithka

private final class MouseRecipientView: NSView {
  var mouseDownCount = 0

  override func mouseDown(with event: NSEvent) {
    mouseDownCount += 1
  }
}

class RunnerTests: XCTestCase {
  func testCopyImageWritesBitmapWithoutFileURL() throws {
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    let bitmap = try XCTUnwrap(
      NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
      ))
    let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))

    XCTAssertTrue(DesktopClipboardImagesPlugin.writeImage(png, to: pasteboard))
    let item = try XCTUnwrap(pasteboard.pasteboardItems?.first)
    XCTAssertEqual(item.data(forType: .png), png)
    XCTAssertNil(item.string(forType: .fileURL))
    XCTAssertNil(item.string(forType: .string))
  }

  func testDesktopImagePasteAndDropPreserveBytesAndRejectNonImages() throws {
    // A private pasteboard avoids reading or changing the user's clipboard.
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    let bitmap = try XCTUnwrap(
      NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
      ))
    let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    let imageItem = NSPasteboardItem()
    imageItem.setData(png, forType: .png)
    let textItem = NSPasteboardItem()
    textItem.setString("not an image", forType: .string)
    pasteboard.writeObjects([imageItem, textItem])
    let images = DesktopClipboardImagesPlugin.readImages(from: pasteboard)
    XCTAssertEqual(images.count, 1)
    let paths = DesktopMediaDropView.storeImages(images)
    defer { paths.forEach { try? FileManager.default.removeItem(atPath: $0) } }
    XCTAssertEqual(paths.count, 1)
    let imageURL = URL(fileURLWithPath: try XCTUnwrap(paths.first))
    XCTAssertEqual(try Data(contentsOf: imageURL), png)

    pasteboard.clearContents()
    pasteboard.writeObjects([imageURL as NSURL])
    let fileImages = DesktopClipboardImagesPlugin.readImages(from: pasteboard)
    XCTAssertEqual(fileImages.count, 1)
    XCTAssertEqual((fileImages.first?["data"] as? FlutterStandardTypedData)?.data, png)
  }

  @MainActor
  func testDesktopDropCoordinatesAreRelativeToTheFlutterView() {
    let parent = MouseRecipientView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    let drop = DesktopMediaDropView(
      frame: NSRect(x: 0, y: 40, width: 800, height: 560)
    ) { _, _ in }
    parent.addSubview(drop)
    let point = drop.flutterPosition(NSPoint(x: 100, y: 500))
    XCTAssertEqual(point["x"], 100)
    XCTAssertEqual(point["y"], 100)
    XCTAssertTrue(drop.nextResponder === parent)
    let click = NSEvent.mouseEvent(
      with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
      windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
    )!
    drop.mouseDown(with: click)
    XCTAssertEqual(parent.mouseDownCount, 1)
  }

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
  func testTrafficLightsCenterOnTheFlutterTitleBarMidline() throws {
    let window = MainFlutterWindow(
      contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
      styleMask: [
        .titled, .closable, .miniaturizable, .resizable, .fullSizeContentView,
      ],
      backing: .buffered,
      defer: false
    )
    window.contentViewController = NSViewController()
    window.titlebarAppearsTransparent = true
    window.orderFront(nil)
    addTeardownBlock { @MainActor in
      window.orderOut(nil)
    }

    window.alignTrafficLightsWithTitleBar()

    let close = try XCTUnwrap(window.standardWindowButton(.closeButton))
    let container = try XCTUnwrap(close.superview)
    let centerInWindow = container.convert(
      NSPoint(x: close.frame.midX, y: close.frame.midY),
      to: nil
    )
    let fromTop = window.frame.height - centerInWindow.y
    XCTAssertEqual(fromTop, 20, accuracy: 0.5)
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
