// AirCrashReports.swift — app crashes for AirFeedback. MetricKit hands each
// crash to a later launch of the app (usually the next one); this file turns
// it into one report and posts it to the app's AirFeedback with the public App
// Key, where it becomes a feedback entry (category crash).
//
// Each report carries: a random report id; when the crash happened; a random
// install id, made once per install and used only to count affected installs;
// the app's version, build and bundle id; the device model, OS, OS build,
// architecture and locale; the exception's type, code and signal, the
// Objective-C exception's name and message (iOS 17 / macOS 14 and later) and
// the termination reason; and up to 64 threads' stacks as binary image +
// offset, the crashed thread first. Unlike the old AirTraffic crash file, the
// message and termination reason ARE sent: they are usually the clue. Nothing else: no account, no file paths, no
// memory contents.
//
// Frames in system libraries are symbolicated here, on the device, against
// the same OS images loaded now. The app's own frames (main executable and
// embedded frameworks) are left as image + offset; the server symbolicates
// them from the dSYMs uploaded with `workers feedback dsyms upload`.
//
// Copy this file and AirDeviceProof.swift into the app target unchanged. No
// packages, no Info.plist entries; iOS 16 / macOS 13 or later. Start it once
// at launch, e.g. in the `App`'s `init()` or
// `application(_:didFinishLaunchingWithOptions:)`, with the `key` and
// `crashEndpoint` that `workers app-key` prints and the Apple team id:
//
//   AirCrashReports.start(apiKey: "REPLACE-WITH-PUBLIC-APP-KEY",
//                         endpoint: "https://apps.air.build/v1/ingest/crashes",
//                         teamID: "ABCDE12345")
//
// With the App Attest capability, each report carries the device's proof
// (AirDeviceProof.swift). Without one (no teamID, the Mac outside the App
// Store, an old device) reports are still sent, and stored as unverified.
//
// The Simulator never delivers crash diagnostics: test on a device, crash,
// then launch again. A report that cannot be sent waits on disk (at most 20)
// for the next launch. When the owner turns crash reports off, the server
// answers 202 and the report is dropped.

import Darwin
import Foundation
import MachO
import MetricKit
import ObjectiveC

/// `nonisolated`: MetricKit calls ``didReceive(_:)`` on a queue of its own,
/// and walking stacks and images has no business on the main actor.
@available(iOS 16.0, macOS 13.0, *)
nonisolated final class AirCrashReports: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    private static let shared = AirCrashReports(folder: defaultFolder())

    /// Where queued reports wait, one JSON body per file.
    private let folder: URL?
    /// Guards everything below: `start` runs on the caller's thread,
    /// `didReceive` on MetricKit's queue, sending in a task.
    private let lock = NSLock()
    private var apiKey = ""
    private var endpoint: URL?
    private var teamID: String?
    private var subscribed = false
    private var sending = false
    private var sendAgain = false

    static let maximumQueued = 20
    /// Under the ingest's 512 KiB, with room for headers.
    static let maximumBody = 500_000

    init(folder: URL?) {
        self.folder = folder
        super.init()
    }

    /// Subscribes to MetricKit and sends what earlier launches left queued.
    static func start(apiKey: String, endpoint: String, teamID: String? = nil) {
        shared.configure(apiKey: apiKey, endpoint: endpoint, teamID: teamID)
        let subscribe = shared.lock.withLock {
            defer { shared.subscribed = true }
            return !shared.subscribed
        }
        if subscribe { MXMetricManager.shared.add(shared) }
        shared.sendQueued()
    }

    func configure(apiKey: String, endpoint: String, teamID: String? = nil) {
        lock.withLock {
            self.apiKey = apiKey
            self.endpoint = URL(string: endpoint)
            self.teamID = teamID
        }
    }

    /// Each crash is dated by its payload's end — the run it happened in,
    /// not the launch that delivers it. Reports are built here, on
    /// MetricKit's queue, because the payloads are not ours to keep.
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let crashes = payloads.flatMap { payload in
            (payload.crashDiagnostics ?? []).map { Crash($0, payloadEnd: payload.timeStampEnd) }
        }
        guard !crashes.isEmpty else { return }
        for body in Self.bodies(of: crashes, installID: installID()) {
            enqueue(body.json, id: body.id)
        }
        sendQueued()
    }

    /// Random per install, so the server can count affected installs
    /// without knowing who they are.
    private func installID() -> String {
        lock.withLock {
            let key = "AirCrashReports.installID"
            if let id = UserDefaults.standard.string(forKey: key), UUID(uuidString: id) != nil { return id }
            let id = UUID().uuidString.lowercased()
            UserDefaults.standard.set(id, forKey: key)
            return id
        }
    }
}

// MARK: - Reports

@available(iOS 16.0, macOS 13.0, *)
nonisolated extension AirCrashReports {
    /// What a report needs from one `MXCrashDiagnostic`, as plain values.
    struct Crash {
        var occurredAt: Date
        var appVersion: String
        var appBuild: String
        var deviceModel: String
        /// MetricKit's form: `iPhone OS 17.1 (21B80)`, `macOS 14.1 (23B74)`.
        var osVersion: String
        var architecture: String
        var exceptionType: Int?
        var exceptionCode: Int?
        var signal: Int?
        var exceptionName: String?
        var exceptionMessage: String?
        var terminationReason: String?
        var callStackTree: Data
    }

    /// One crash, as `POST /v1/ingest/crashes` takes it.
    struct Report: Encodable {
        var id: String
        var occurredAt: String
        var installID: String
        var app: App
        var device: Device
        var exception: Exception
        var threads: [Thread]
        var images: [Image]

        struct App: Encodable {
            var version: String
            var build: String
            var bundleID: String
        }

        struct Device: Encodable {
            var model: String
            var os: String
            var osVersion: String
            var osBuild: String
            var arch: String
            var locale: String
        }

        /// Written by hand so an absent value is an explicit `null`.
        struct Exception: Encodable {
            var type: Int?
            var code: Int?
            var signal: Int?
            var name: String?
            var message: String?
            var terminationReason: String?

            enum CodingKeys: String, CodingKey {
                case type, code, signal, name, message, terminationReason
            }

            func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(type, forKey: .type)
                try container.encode(code, forKey: .code)
                try container.encode(signal, forKey: .signal)
                try container.encode(name, forKey: .name)
                try container.encode(message, forKey: .message)
                try container.encode(terminationReason, forKey: .terminationReason)
            }
        }

        struct Thread: Encodable {
            var crashed: Bool
            var frames: [Frame]
        }

        /// `symbol` and `symbolOffset` are left out unless resolved here.
        struct Frame: Encodable {
            var image: String
            var uuid: UUID
            var offset: UInt64
            var inApp: Bool
            var symbol: String?
            var symbolOffset: UInt64?
        }

        struct Image: Encodable, Hashable {
            var name: String
            var uuid: UUID
            var inApp: Bool
        }
    }

    /// The ingest bodies of one delivery's crashes. They are symbolicated
    /// together so a system frame shared by several crashes is resolved once.
    /// A crash without a single frame is not sent: the ingest refuses it.
    static func bodies(of crashes: [Crash], installID: String) -> [(id: String, json: Data)] {
        let loaded = LoadedImages()
        var reports = crashes.map { report(of: $0, installID: installID, loaded: loaded) }.filter { !$0.threads.isEmpty }
        var keys = Set<SystemSymbols.Key>()
        for report in reports {
            for thread in report.threads {
                for frame in thread.frames where !frame.inApp {
                    keys.insert(SystemSymbols.Key(uuid: frame.uuid, offset: frame.offset))
                }
            }
        }
        let symbols = SystemSymbols.resolve(keys, in: loaded)
        for r in reports.indices {
            for t in reports[r].threads.indices {
                for f in reports[r].threads[t].frames.indices {
                    let frame = reports[r].threads[t].frames[f]
                    guard !frame.inApp, let symbol = symbols[SystemSymbols.Key(uuid: frame.uuid, offset: frame.offset)] else {
                        continue
                    }
                    reports[r].threads[t].frames[f].symbol = symbol.name
                    reports[r].threads[t].frames[f].symbolOffset = symbol.offset
                }
            }
        }
        return reports.compactMap { report in encoded(report).map { (report.id, $0) } }
    }

    static func report(of crash: Crash, installID: String, loaded: LoadedImages) -> Report {
        let os = operatingSystem(crash.osVersion, model: crash.deviceModel)
        let threads = threads(scan(crash.callStackTree) ?? [], loaded: loaded)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        func capped(_ text: String?, _ length: Int) -> String? {
            text.flatMap { $0.isEmpty ? nil : String($0.prefix(length)) }
        }
        return Report(
            id: UUID().uuidString.lowercased(),
            occurredAt: formatter.string(from: min(crash.occurredAt, Date())),
            installID: installID,
            app: Report.App(version: crash.appVersion, build: crash.appBuild, bundleID: Bundle.main.bundleIdentifier ?? ""),
            device: Report.Device(
                model: crash.deviceModel,
                os: os.name,
                osVersion: os.version,
                osBuild: os.build,
                arch: crash.architecture,
                locale: Locale.current.identifier
            ),
            exception: Report.Exception(
                type: crash.exceptionType,
                code: crash.exceptionCode,
                signal: crash.signal,
                name: capped(crash.exceptionName, 256),
                message: capped(crash.exceptionMessage, 1024),
                terminationReason: capped(crash.terminationReason, 512)
            ),
            threads: threads,
            images: images(of: threads)
        )
    }

    /// The crashed thread first with up to 256 frames, then up to 63 others
    /// with up to 64 each; threads without frames are dropped.
    static func threads(_ scanned: [ScannedThread], loaded: LoadedImages) -> [Report.Thread] {
        var scanned = scanned.filter { !$0.frames.isEmpty }
        if let crashed = scanned.firstIndex(where: \.crashed) {
            scanned.insert(scanned.remove(at: crashed), at: 0)
        }
        let hasCrashed = scanned.first?.crashed == true
        var inApp: [UUID: Bool] = [:]
        return scanned.prefix(64).enumerated().map { index, thread in
            let isCrashed = index == 0 && hasCrashed
            let frames = thread.frames.prefix(isCrashed ? 256 : 64).map { frame in
                let image = frame.image.isEmpty ? "???" : frame.image
                let own = inApp[frame.uuid] ?? loaded.isInApp(image: image, uuid: frame.uuid)
                inApp[frame.uuid] = own
                return Report.Frame(image: image, uuid: frame.uuid, offset: frame.offset, inApp: own)
            }
            return Report.Thread(crashed: isCrashed, frames: frames)
        }
    }

    /// Each image the frames reach, once, in the order first reached.
    static func images(of threads: [Report.Thread]) -> [Report.Image] {
        var seen = Set<Report.Image>()
        var images: [Report.Image] = []
        for frame in threads.lazy.flatMap(\.frames) {
            let image = Report.Image(name: frame.image, uuid: frame.uuid, inApp: frame.inApp)
            if seen.insert(image).inserted { images.append(image) }
        }
        return images
    }

    /// The JSON body, trimmed to fit the ingest's size limit: threads go from
    /// the end first, then the crashed thread's deepest frames.
    static func encoded(_ report: Report) -> Data? {
        var report = report
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        while true {
            guard let json = try? encoder.encode(report) else { return nil }
            let frames = report.threads.reduce(0) { $0 + $1.frames.count }
            guard json.count > maximumBody, frames > 1 else { return json }
            if report.threads.count > 1 {
                report.threads.removeLast(max(1, (report.threads.count - 1) / 4))
            } else {
                report.threads[0].frames.removeLast(max(1, frames / 4))
            }
            report.images = images(of: report.threads)
        }
    }

    /// `iPhone OS 17.1 (21B80)` → `iOS`, `17.1`, `21B80` (`iPadOS` on an
    /// iPad); `macOS 14.1 (23B74)` → `macOS`, `14.1`, `23B74`.
    static func operatingSystem(_ text: String, model: String) -> (name: String, version: String, build: String) {
        var head = Substring(text)
        var build = ""
        if let open = text.lastIndex(of: "("), let close = text.lastIndex(of: ")"), open < close {
            build = text[text.index(after: open) ..< close].trimmingCharacters(in: .whitespaces)
            if build.hasPrefix("Build ") { build.removeFirst(6) }
            head = text[..<open]
        }
        let words = head.split(separator: " ")
        let versionAt = words.lastIndex { word in
            word.first?.isNumber == true && word.allSatisfy { $0.isNumber || $0 == "." }
        }
        let version = versionAt.map { String(words[$0]) } ?? ""
        let name = words[..<(versionAt ?? words.endIndex)].joined(separator: " ")
        switch name.lowercased() {
        case "iphone os", "ios": return (model.hasPrefix("iPad") ? "iPadOS" : "iOS", version, build)
        case "ipados": return ("iPadOS", version, build)
        case "macos", "mac os x", "mac os", "os x": return ("macOS", version, build)
        case "xros", "visionos": return ("visionOS", version, build)
        case "tvos": return ("tvOS", version, build)
        case "watchos": return ("watchOS", version, build)
        case "", "version": return (thisPlatform, version, build)
        default: return (name, version, build)
        }
    }

    private static var thisPlatform: String {
        #if os(macOS)
        "macOS"
        #elseif os(visionOS)
        "visionOS"
        #else
        "iOS"
        #endif
    }
}

@available(iOS 16.0, macOS 13.0, *)
nonisolated extension AirCrashReports.Crash {
    init(_ crash: MXCrashDiagnostic, payloadEnd: Date) {
        let meta = crash.metaData
        var name: String?
        var message: String?
        if #available(iOS 17.0, macOS 14.0, *), let reason = crash.exceptionReason {
            name = reason.exceptionName
            message = reason.composedMessage
        }
        self.init(
            occurredAt: payloadEnd,
            appVersion: crash.applicationVersion,
            appBuild: meta.applicationBuildVersion,
            deviceModel: meta.deviceType,
            osVersion: meta.osVersion,
            architecture: meta.platformArchitecture,
            exceptionType: crash.exceptionType.map { Int(truncatingIfNeeded: $0.int64Value) },
            exceptionCode: crash.exceptionCode.map { Int(truncatingIfNeeded: $0.int64Value) },
            signal: crash.signal.map { Int(truncatingIfNeeded: $0.int64Value) },
            exceptionName: name,
            exceptionMessage: message,
            terminationReason: crash.terminationReason,
            callStackTree: crash.callStackTree.jsonRepresentation()
        )
    }
}

// MARK: - Call stack tree

@available(iOS 16.0, macOS 13.0, *)
nonisolated extension AirCrashReports {
    struct ScannedFrame: Equatable {
        var image: String
        var uuid: UUID
        var offset: UInt64
    }

    struct ScannedThread: Equatable {
        var crashed: Bool
        var frames: [ScannedFrame]
    }

    /// What an object being read has shown so far.
    private struct OpenObject {
        var order: Int
        var isThread: Bool
        var key: String?
        var name: String?
        var uuid: UUID?
        var offset: UInt64?
        var attributed = false
    }

    private enum Container {
        case object
        case array(key: String?)
    }

    /// Reads MetricKit's call stack tree flat. The tree nests a crash's stack
    /// one level per frame, and `JSONSerialization` refuses past 255 levels,
    /// so a stack overflow — the deepest stack there is — would arrive with
    /// no stack. This walks the bytes once with a stack of its own and no
    /// depth limit, keeping each `callStacks` entry's `threadAttributed` and
    /// each frame's `binaryName`, `binaryUUID` and
    /// `offsetIntoBinaryTextSegment`, in the order the frames open (the
    /// faulting frame first). Nil when the bytes are not well-formed.
    static func scan(_ json: Data) -> [ScannedThread]? {
        let bytes = [UInt8](json)
        var index = 0
        var containers: [Container] = []
        var objects: [OpenObject] = []
        var threads: [(crashed: Bool, frames: [(order: Int, frame: ScannedFrame)])] = []
        var opened = 0

        /// A key or value just read, given to the object it belongs to.
        func take(_ value: String) {
            guard case .object = containers.last, !objects.isEmpty else { return }
            guard let key = objects[objects.count - 1].key else {
                objects[objects.count - 1].key = value
                return
            }
            switch key {
            case "binaryName": objects[objects.count - 1].name = value
            case "binaryUUID": objects[objects.count - 1].uuid = UUID(uuidString: value)
            case "offsetIntoBinaryTextSegment": objects[objects.count - 1].offset = UInt64(value)
            case "threadAttributed": objects[objects.count - 1].attributed = value == "true"
            default: break
            }
            objects[objects.count - 1].key = nil
        }

        /// A container opening as the current object's value takes its key.
        func consumeKey() -> String? {
            guard case .object = containers.last, !objects.isEmpty else { return nil }
            defer { objects[objects.count - 1].key = nil }
            return objects[objects.count - 1].key
        }

        while index < bytes.count {
            switch bytes[index] {
            case UInt8(ascii: "{"):
                var isThread = false
                if case let .array(key) = containers.last, key == "callStacks" { isThread = true }
                _ = consumeKey()
                containers.append(.object)
                objects.append(OpenObject(order: opened, isThread: isThread))
                opened += 1
                if isThread { threads.append((false, [])) }
                index += 1
            case UInt8(ascii: "}"):
                guard case .object = containers.popLast(), let object = objects.popLast() else { return nil }
                if object.isThread, !threads.isEmpty {
                    threads[threads.count - 1].crashed = object.attributed
                } else if let uuid = object.uuid, let offset = object.offset, !threads.isEmpty {
                    let frame = ScannedFrame(image: object.name ?? "", uuid: uuid, offset: offset)
                    threads[threads.count - 1].frames.append((object.order, frame))
                }
                index += 1
            case UInt8(ascii: "["):
                containers.append(.array(key: consumeKey()))
                index += 1
            case UInt8(ascii: "]"):
                guard case .array = containers.popLast() else { return nil }
                index += 1
            case UInt8(ascii: "\""):
                var end = index + 1
                while end < bytes.count, bytes[end] != UInt8(ascii: "\"") {
                    end += bytes[end] == UInt8(ascii: "\\") ? 2 : 1
                }
                guard end < bytes.count else { return nil }
                take(String(decoding: bytes[(index + 1) ..< end], as: UTF8.self))
                index = end + 1
            case UInt8(ascii: ","), UInt8(ascii: ":"), UInt8(ascii: " "), 0x09, 0x0A, 0x0D:
                index += 1
            default:
                // A number, `true`, `false` or `null`: up to the next delimiter.
                let start = index
                while index < bytes.count, !delimiters.contains(bytes[index]) { index += 1 }
                guard index > start else { return nil }
                take(String(decoding: bytes[start ..< index], as: UTF8.self))
            }
        }
        guard containers.isEmpty else { return nil }
        // Frames close innermost first; their opening order is the stack's.
        return threads.map { thread in
            ScannedThread(crashed: thread.crashed, frames: thread.frames.sorted { $0.order < $1.order }.map(\.frame))
        }
    }

    private static let delimiters = Set(",:{}[]\" \t\r\n".utf8)
}

// MARK: - Images

@available(iOS 16.0, macOS 13.0, *)
nonisolated extension AirCrashReports {
    struct LoadedImage {
        /// The mach header's address, which is where `__TEXT` starts and
        /// what MetricKit's offsets count from.
        var header: UInt
        var textSize: UInt
        var path: String
    }

    /// The images loaded in this process now, read once per delivery, and
    /// which images are the app's own.
    struct LoadedImages {
        private(set) var byUUID: [UUID: LoadedImage] = [:]
        private var appUUIDs = Set<UUID>()
        private var appNames = Set<String>()

        init() {
            let root = Self.appRoot()
            let count = min(_dyld_image_count(), 100_000)
            for index in 0 ..< count {
                guard let header = _dyld_get_image_header(index), let name = _dyld_get_image_name(index),
                      let (uuid, textSize) = Self.identity(of: header)
                else { continue }
                let path = String(cString: name)
                byUUID[uuid] = LoadedImage(header: UInt(bitPattern: header), textSize: textSize, path: path)
                if Self.normalized(path).hasPrefix(root + "/") {
                    appUUIDs.insert(uuid)
                    appNames.insert((path as NSString).lastPathComponent)
                }
            }
            appNames.formUnion(Self.binaryNames(inBundleAt: root))
        }

        /// The app's own: loaded from inside the app bundle now, or — for a
        /// crash in an older build whose UUIDs are gone — named like one of
        /// the bundle's binaries and not loaded from elsewhere.
        func isInApp(image name: String, uuid: UUID) -> Bool {
            if appUUIDs.contains(uuid) { return true }
            if byUUID[uuid] != nil { return false }
            return appNames.contains(name)
        }

        /// The outermost `.app` around this process, so an extension's frames
        /// in the containing app's shared frameworks count as the app's.
        private static func appRoot() -> String {
            let path = normalized(Bundle.main.bundleURL.resolvingSymlinksInPath().path)
            let components = path.split(separator: "/", omittingEmptySubsequences: true)
            guard let app = components.firstIndex(where: { $0.hasSuffix(".app") }) else { return path }
            return "/" + components[...app].joined(separator: "/")
        }

        /// dyld and `Bundle` disagree on `/private/var` versus `/var`.
        private static func normalized(_ path: String) -> String {
            path.hasPrefix("/private/") ? String(path.dropFirst(8)) : path
        }

        private static func binaryNames(inBundleAt root: String) -> Set<String> {
            var names = Set<String>()
            let bundle = Bundle(path: root)
            for executable in [Bundle.main.executableURL, bundle?.executableURL] {
                if let name = executable?.lastPathComponent { names.insert(name) }
            }
            var folders = [bundle?.privateFrameworksPath, bundle?.builtInPlugInsPath].compactMap { $0 }
            #if os(macOS)
            folders += [root + "/Contents/MacOS", root + "/Contents/XPCServices"]
            #endif
            for folder in folders {
                let items = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
                for item in items.prefix(512) {
                    names.insert(item.hasSuffix(".dylib") ? item : (item as NSString).deletingPathExtension)
                }
            }
            return names
        }

        /// An image's LC_UUID and `__TEXT` size, read from its load commands
        /// with every length checked against the header's.
        static func identity(of header: UnsafePointer<mach_header>) -> (UUID, UInt)? {
            guard header.pointee.magic == MH_MAGIC_64 else { return nil }
            let commandCount = Int(header.pointee.ncmds)
            let commandsSize = Int(header.pointee.sizeofcmds)
            guard commandCount < 65_536, commandsSize < 64 << 20 else { return nil }
            var offset = MemoryLayout<mach_header_64>.size
            let end = offset + commandsSize
            let base = UnsafeRawPointer(header)
            var uuid: UUID?
            var textSize: UInt?
            for _ in 0 ..< commandCount {
                guard offset + 8 <= end else { break }
                let command = base.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
                let size = Int(base.loadUnaligned(fromByteOffset: offset + 4, as: UInt32.self))
                guard size >= 8, offset + size <= end else { break }
                if command == UInt32(LC_UUID), size >= MemoryLayout<uuid_command>.size {
                    var bytes: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
                    withUnsafeMutableBytes(of: &bytes) { $0.copyMemory(from: UnsafeRawBufferPointer(start: base + offset + 8, count: 16)) }
                    uuid = UUID(uuid: bytes)
                } else if command == UInt32(LC_SEGMENT_64), size >= MemoryLayout<segment_command_64>.size {
                    let name = UnsafeRawBufferPointer(start: base + offset + 8, count: 16)
                    if name.elementsEqual("__TEXT".utf8 + [UInt8](repeating: 0, count: 10)) {
                        textSize = UInt(base.loadUnaligned(fromByteOffset: offset + 32, as: UInt64.self))
                    }
                }
                offset += size
            }
            guard let uuid, let textSize else { return nil }
            return (uuid, textSize)
        }
    }
}

// MARK: - System symbols

@available(iOS 16.0, macOS 13.0, *)
nonisolated extension AirCrashReports {
    /// Names system frames on the device, the way PLCrashReporter does:
    /// the image with the frame's UUID must be loaded now (an OS update since
    /// the crash, or an image this run never loaded, leaves the frame as
    /// image + offset). `dladdr` gives the nearest symbol the image exports,
    /// which in the shared cache is often `<redacted>` or a distant function,
    /// so the closest Objective-C method at or below the address is looked
    /// up too, and the nearer start wins.
    enum SystemSymbols {
        struct Key: Hashable {
            var uuid: UUID
            var offset: UInt64
        }

        struct Symbol: Equatable {
            var name: String
            var offset: UInt64
        }

        /// Each key resolved once; keys whose image is not loaded now, or
        /// whose offset falls outside its `__TEXT`, are left out.
        static func resolve(_ keys: Set<Key>, in loaded: LoadedImages) -> [Key: Symbol] {
            var targets: [(key: Key, image: LoadedImage, address: UInt)] = []
            for key in keys {
                guard let image = loaded.byUUID[key.uuid], key.offset < UInt64(image.textSize) else { continue }
                targets.append((key, image, image.header &+ UInt(key.offset)))
            }
            guard !targets.isEmpty else { return [:] }
            var seen = Set<UInt>()
            let images = targets.map(\.image).filter { seen.insert($0.header).inserted }
            let methods = ObjCMethods(images: images)
            let demangle = swiftDemangle()
            var symbols: [Key: Symbol] = [:]
            for target in targets {
                symbols[target.key] = symbol(at: target.address, in: target.image, methods: methods, demangle: demangle)
            }
            return symbols
        }

        static func symbol(at address: UInt, in image: LoadedImage, methods: ObjCMethods, demangle: Demangle?) -> Symbol? {
            var best: (name: String, start: UInt, mangled: Bool)?
            var info = Dl_info()
            if dladdr(UnsafeRawPointer(bitPattern: address), &info) != 0,
               UInt(bitPattern: info.dli_fbase) == image.header,
               let name = info.dli_sname, let start = info.dli_saddr.map({ strip(UInt(bitPattern: $0)) }),
               start <= address, start >= image.header {
                let text = String(cString: name)
                if text != "<redacted>" { best = (text, start, true) }
            }
            if let method = methods.closest(atOrBelow: address, in: image), method.start > best?.start ?? 0 {
                best = (method.name, method.start, false)
            }
            guard let best else { return nil }
            let name = best.mangled ? demangled(best.name, with: demangle) : best.name
            return Symbol(name: String(name.prefix(1024)), offset: UInt64(address - best.start))
        }

        typealias Demangle = @convention(c) (
            UnsafePointer<CChar>?, Int, UnsafeMutablePointer<CChar>?, UnsafeMutablePointer<Int>?, UInt32
        ) -> UnsafeMutablePointer<CChar>?

        /// The Swift runtime's demangler, looked up rather than linked: it is
        /// not public API, and a missing one just leaves names mangled.
        static func swiftDemangle() -> Demangle? {
            dlsym(UnsafeMutableRawPointer(bitPattern: -2), "swift_demangle").map { unsafeBitCast($0, to: Demangle.self) }
        }

        static func demangled(_ name: String, with demangle: Demangle?) -> String {
            guard let demangle, ["$s", "_$s", "$S", "_$S", "$e", "_T0"].contains(where: name.hasPrefix) else { return name }
            return name.withCString { mangled in
                guard let result = demangle(mangled, strlen(mangled), nil, nil, 0) else { return name }
                defer { free(result) }
                return String(cString: result)
            }
        }

        /// Drops pointer-authentication bits; user addresses fit in 47 bits
        /// on every 64-bit Apple platform.
        static func strip(_ pointer: UInt) -> UInt {
            pointer & 0x0000_7FFF_FFFF_FFFF
        }
    }

    /// The Objective-C methods whose implementations lie in the given images,
    /// sorted by start per image. Read from the classes those images define,
    /// plus libobjc's root classes: categories on `NSObject` (CoreFoundation's
    /// `-[NSObject(NSObject) doesNotRecognizeSelector:]`, say) live in another
    /// image than their class. Only runtime calls that never message a class
    /// are used: no `+initialize` runs, and no class object is retained.
    struct ObjCMethods {
        struct Method {
            var start: UInt
            /// From `objc_copyClassNamesForImage`: owned by the runtime, and
            /// already demangled for Swift classes.
            var className: UnsafePointer<CChar>
            var selector: Selector
            var isMeta: Bool
        }

        private var byImage: [UInt: [Method]] = [:]

        /// The runtime's class functions on raw pointers. Swift's imports take
        /// `AnyClass`: making one wraps a plain Objective-C class in Swift
        /// metadata, and passing it as `Any` retains it — a message some root
        /// classes (CoreFoundation's `__NSMessageBuilder`) answer by aborting.
        private struct Runtime {
            typealias LookUp = @convention(c) (UnsafePointer<CChar>) -> UnsafeRawPointer?
            typealias GetClass = @convention(c) (UnsafeRawPointer) -> UnsafeRawPointer?
            typealias CopyMethods = @convention(c) (
                UnsafeRawPointer, UnsafeMutablePointer<UInt32>
            ) -> UnsafeMutablePointer<OpaquePointer>?

            let lookUp: LookUp
            let getClass: GetClass
            let copyMethods: CopyMethods

            init?() {
                func function<T>(_ name: String, _ type: T.Type) -> T? {
                    dlsym(UnsafeMutableRawPointer(bitPattern: -2), name).map { unsafeBitCast($0, to: type) }
                }
                guard let lookUp = function("objc_lookUpClass", LookUp.self),
                      let getClass = function("object_getClass", GetClass.self),
                      let copyMethods = function("class_copyMethodList", CopyMethods.self)
                else { return nil }
                self.lookUp = lookUp
                self.getClass = getClass
                self.copyMethods = copyMethods
            }
        }

        init(images: [LoadedImage]) {
            guard let runtime = Runtime() else { return }
            let ranges = images.map { (start: $0.header, end: $0.header &+ $0.textSize) }.sorted { $0.start < $1.start }
            /// The image whose `__TEXT` holds an implementation.
            func image(of start: UInt) -> UInt? {
                var low = 0, high = ranges.count
                while low < high {
                    let middle = (low + high) / 2
                    if ranges[middle].start <= start { low = middle + 1 } else { high = middle }
                }
                guard low > 0, start < ranges[low - 1].end else { return nil }
                return ranges[low - 1].start
            }
            func add(methodsOf cls: UnsafeRawPointer, named className: UnsafePointer<CChar>, isMeta: Bool) {
                var count: UInt32 = 0
                guard let list = runtime.copyMethods(cls, &count) else { return }
                defer { free(list) }
                for index in 0 ..< Int(min(count, 100_000)) {
                    let start = SystemSymbols.strip(UInt(bitPattern: Int(bitPattern: method_getImplementation(list[index]))))
                    guard let header = image(of: start) else { continue }
                    byImage[header, default: []].append(
                        Method(start: start, className: className, selector: method_getName(list[index]), isMeta: isMeta)
                    )
                }
            }
            var paths = images.map(\.path)
            if let objc = class_getImageName(NSObject.self).map({ String(cString: $0) }), !paths.contains(objc) {
                paths.append(objc)
            }
            for path in paths {
                var count: UInt32 = 0
                guard let names = objc_copyClassNamesForImage(path, &count) else { continue }
                defer { free(names) }
                for index in 0 ..< Int(min(count, 500_000)) {
                    guard let cls = runtime.lookUp(names[index]) else { continue }
                    add(methodsOf: cls, named: names[index], isMeta: false)
                    if let meta = runtime.getClass(cls) { add(methodsOf: meta, named: names[index], isMeta: true) }
                }
            }
            for header in byImage.keys { byImage[header]?.sort { $0.start < $1.start } }
        }

        /// `-[Class selector]` or `+[Class selector]` and its start.
        func closest(atOrBelow address: UInt, in image: LoadedImage) -> (name: String, start: UInt)? {
            guard let methods = byImage[image.header] else { return nil }
            var low = 0, high = methods.count
            while low < high {
                let middle = (low + high) / 2
                if methods[middle].start <= address { low = middle + 1 } else { high = middle }
            }
            guard low > 0 else { return nil }
            let method = methods[low - 1]
            let name = "\(method.isMeta ? "+" : "-")[\(String(cString: method.className)) \(String(cString: sel_getName(method.selector)))]"
            return (name, method.start)
        }
    }
}

// MARK: - Queue

@available(iOS 16.0, macOS 13.0, *)
nonisolated extension AirCrashReports {
    /// Application Support/AirCrashReports, kept out of backups. On the Mac,
    /// under the bundle id first: outside the sandbox that folder is shared.
    static func defaultFolder() -> URL? {
        guard var folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        #if os(macOS)
        folder = folder.appending(path: Bundle.main.bundleIdentifier ?? "AirCrash", directoryHint: .isDirectory)
        #endif
        return folder.appending(path: "AirCrashReports", directoryHint: .isDirectory)
    }

    /// Writes one report and drops the oldest beyond ``maximumQueued``. The
    /// file holds the exact body, so a retry sends the same report id.
    func enqueue(_ json: Data, id: String) {
        guard var folder else { return }
        let files = FileManager.default
        if !files.fileExists(atPath: folder.path) {
            try? files.createDirectory(at: folder, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? folder.setResourceValues(values)
        }
        let stamp = String(UInt64(max(0, Date().timeIntervalSince1970 * 1000)))
        let name = String(repeating: "0", count: max(0, 15 - stamp.count)) + stamp + "-" + id + ".json"
        try? json.write(to: folder.appending(path: name, directoryHint: .notDirectory), options: .atomic)
        for file in queued().dropLast(Self.maximumQueued) {
            try? files.removeItem(at: file)
        }
    }

    /// Oldest first: the names start with the time they were queued.
    func queued() -> [URL] {
        guard let folder else { return [] }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { $0.hasSuffix(".json") }.sorted().map {
            folder.appending(path: $0, directoryHint: .notDirectory)
        }
    }

    /// One pass over the queue at a time; a request while one runs gets
    /// one more pass after it, never a second sender.
    private func sendQueued() {
        let begin = lock.withLock {
            if sending { sendAgain = true }
            defer { sending = true }
            return !sending
        }
        guard begin else { return }
        Task.detached(priority: .utility) {
            while true {
                await self.sendPass()
                let again = self.lock.withLock {
                    defer { self.sendAgain = false }
                    self.sending = self.sendAgain
                    return self.sendAgain
                }
                if !again { return }
            }
        }
    }

    private static let notBeforeKey = "AirCrashReports.notBefore"

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    /// Posts each queued report once, oldest first. Accepted (2xx, including
    /// 202 when the owner has crash reports off) or refused for good (4xx)
    /// deletes it; 408, 5xx and other answers keep it for the next launch.
    /// No network, or 429, ends the pass: the rest would fare the same.
    func sendPass() async {
        let (apiKey, endpoint, teamID) = lock.withLock { (self.apiKey, self.endpoint, self.teamID) }
        guard let endpoint, !apiKey.isEmpty else { return }
        if let notBefore = UserDefaults.standard.object(forKey: Self.notBeforeKey) as? Date, notBefore > Date() {
            return
        }
        for file in queued() {
            // Unreadable now (still locked, say) is not the same as gone.
            guard let body = try? Data(contentsOf: file) else { continue }
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            // A fresh assertion per post over the exact bytes; none is fine.
            let proof = await AirDeviceProof.headers(for: body, endpoint: endpoint, appKey: apiKey, teamID: teamID)
            for (name, value) in proof {
                request.setValue(value, forHTTPHeaderField: name)
            }
            guard let (_, response) = try? await Self.session.upload(for: request, from: body),
                  let status = (response as? HTTPURLResponse)?.statusCode
            else { return }
            if !proof.isEmpty {
                await AirDeviceProof.handle(status: (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "X-Attest-Status"))
            }
            switch status {
            case 200 ..< 300, 400 ..< 408, 409 ..< 429, 430 ..< 500:
                try? FileManager.default.removeItem(at: file)
            case 429:
                let seconds = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After").flatMap { Int($0) } ?? 60
                let wait = TimeInterval(min(max(seconds, 1), 86_400))
                UserDefaults.standard.set(Date().addingTimeInterval(wait), forKey: Self.notBeforeKey)
                return
            default:
                continue
            }
        }
    }
}
