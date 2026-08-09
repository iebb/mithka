#if os(macOS)
import FlutterMacOS
#else
import Flutter
#endif
import Foundation

final class HandoffBridge: NSObject, NSUserActivityDelegate {
  static let shared = HandoffBridge()
  static let activityType = "ad.neko.mithka.chat"

  private var channel: FlutterMethodChannel?
  private var currentActivity: NSUserActivity?
  private var currentPayload: HandoffPayload?
  private var pendingContinuation: PendingHandoffContinuation?
  private var streamTransactions: [ObjectIdentifier: AnyObject] = [:]

  private override init() {
    super.init()
  }

  func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "mithka/handoff", binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
  }

  func accept(_ userActivity: NSUserActivity) -> Bool {
    guard
      userActivity.activityType == Self.activityType,
      let payload = HandoffPayload(userInfo: userActivity.userInfo)
    else {
      return false
    }
    pendingContinuation = PendingHandoffContinuation(
      activity: userActivity,
      payload: payload
    )
    channel?.invokeMethod("continueActivity", arguments: payload.dictionary)
    return true
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "updateActivity":
      guard let arguments = call.arguments as? [String: Any] else {
        result(Self.invalidArgumentsError)
        return
      }
      updateActivity(arguments: arguments, result: result)
    case "clearActivity":
      clearActivity()
      result(nil)
    case "takePendingActivity":
      result(pendingContinuation?.payload.dictionary)
    case "completeActivity":
      guard
        let arguments = call.arguments as? [String: Any],
        let activityID = arguments["activityId"] as? String
      else {
        result(Self.invalidArgumentsError)
        return
      }
      if pendingContinuation?.payload.activityID == activityID {
        pendingContinuation = nil
      }
      result(nil)
    case "requestSession":
      requestSession(arguments: call.arguments, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func updateActivity(
    arguments: [String: Any],
    result: @escaping FlutterResult
  ) {
    let activityID: String
    if
      let currentPayload,
      currentPayload.matches(arguments: arguments)
    {
      activityID = currentPayload.activityID
    } else {
      activityID = UUID().uuidString
    }
    guard let payload = HandoffPayload(arguments: arguments, activityID: activityID) else {
      result(Self.invalidArgumentsError)
      return
    }

    if let activity = currentActivity, currentPayload?.activityID == payload.activityID {
      currentPayload = payload
      configure(activity, payload: payload)
      activity.needsSave = true
      result(nil)
      return
    }

    clearActivity()
    let activity = NSUserActivity(activityType: Self.activityType)
    currentActivity = activity
    currentPayload = payload
    configure(activity, payload: payload)
    activity.becomeCurrent()
    result(nil)
  }

  private func configure(_ activity: NSUserActivity, payload: HandoffPayload) {
    activity.title = "Mithka"
    activity.userInfo = payload.dictionary
    activity.requiredUserInfoKeys = Set(HandoffPayload.requiredKeys)
    activity.isEligibleForHandoff = true
    activity.isEligibleForSearch = false
    activity.isEligibleForPublicIndexing = false
#if !os(macOS)
    activity.isEligibleForPrediction = false
#endif
    activity.supportsContinuationStreams = true
    activity.delegate = self
  }

  private func clearActivity() {
    currentActivity?.resignCurrent()
    currentActivity?.invalidate()
    currentActivity = nil
    currentPayload = nil
  }

  private func requestSession(arguments: Any?, result: @escaping FlutterResult) {
    guard
      let arguments = arguments as? [String: Any],
      let requestedPayload = HandoffPayload(arguments: arguments),
      let pending = pendingContinuation,
      pending.payload == requestedPayload
    else {
      result(Self.sessionUnavailableError)
      return
    }

    pending.activity.getContinuationStreams { [weak self] input, output, error in
      DispatchQueue.main.async {
        guard let self, error == nil, let input, let output else {
          result(Self.sessionUnavailableError)
          return
        }
        let reader = HandoffStreamReader(input: input, output: output) {
          [weak self] reader, response in
          self?.streamTransactions.removeValue(forKey: ObjectIdentifier(reader))
          switch response {
          case .success(let data):
            guard
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any],
              let sessionString = dictionary["sessionString"] as? String,
              !sessionString.isEmpty
            else {
              result(Self.sessionUnavailableError)
              return
            }
            result(["sessionString": sessionString])
          case .failure:
            result(Self.sessionUnavailableError)
          }
        }
        self.streamTransactions[ObjectIdentifier(reader)] = reader
        reader.start()
      }
    }
  }

  func userActivityWillSave(_ userActivity: NSUserActivity) {
    guard userActivity === currentActivity, let currentPayload else { return }
    userActivity.userInfo = currentPayload.dictionary
  }

  func userActivity(
    _ userActivity: NSUserActivity,
    didReceive inputStream: InputStream,
    outputStream: OutputStream
  ) {
    guard
      userActivity.activityType == Self.activityType,
      let payload = HandoffPayload(userInfo: userActivity.userInfo),
      let channel
    else {
      writeSessionResponse(nil, input: inputStream, output: outputStream)
      return
    }

    channel.invokeMethod("exportSession", arguments: payload.dictionary) { [weak self] value in
      let sessionString = (value as? [String: Any])?["sessionString"] as? String
      self?.writeSessionResponse(sessionString, input: inputStream, output: outputStream)
    }
  }

  private func writeSessionResponse(
    _ sessionString: String?,
    input: InputStream,
    output: OutputStream
  ) {
    let response: [String: Any]
    if let sessionString, !sessionString.isEmpty {
      response = ["version": HandoffPayload.version, "sessionString": sessionString]
    } else {
      response = ["version": HandoffPayload.version, "error": "session_unavailable"]
    }
    guard var data = try? JSONSerialization.data(withJSONObject: response) else {
      input.close()
      output.close()
      return
    }
    data.append(0x0A)
    let writer = HandoffStreamWriter(input: input, output: output, data: data) {
      [weak self] writer in
      self?.streamTransactions.removeValue(forKey: ObjectIdentifier(writer))
    }
    streamTransactions[ObjectIdentifier(writer)] = writer
    writer.start()
  }

  private static let invalidArgumentsError = FlutterError(
    code: "handoff_invalid_activity",
    message: "The Handoff activity is invalid.",
    details: nil
  )

  private static let sessionUnavailableError = FlutterError(
    code: "handoff_session_unavailable",
    message: "The source device could not transfer this account session.",
    details: nil
  )
}

private struct PendingHandoffContinuation {
  let activity: NSUserActivity
  let payload: HandoffPayload
}

struct HandoffPayload: Equatable {
  static let version = 1
  static let requiredKeys = ["version", "activityId", "accountUserId", "chatId"]

  let activityID: String
  let accountUserID: Int64
  let chatID: Int64
  let messageID: Int64?

  init?(arguments: [String: Any], activityID: String? = nil) {
    guard
      Self.integer(arguments["version"]) == Int64(Self.version),
      let accountUserID = Self.integer(arguments["accountUserId"]),
      accountUserID > 0,
      let chatID = Self.integer(arguments["chatId"]),
      chatID != 0
    else {
      return nil
    }
    let resolvedActivityID = activityID ?? arguments["activityId"] as? String
    guard
      let resolvedActivityID,
      !resolvedActivityID.isEmpty,
      resolvedActivityID.utf8.count <= 128
    else {
      return nil
    }
    let messageID = Self.integer(arguments["messageId"])
    if arguments["messageId"] != nil {
      guard let messageID, messageID > 0 else { return nil }
    }
    self.activityID = resolvedActivityID
    self.accountUserID = accountUserID
    self.chatID = chatID
    self.messageID = messageID
  }

  init?(userInfo: [AnyHashable: Any]?) {
    guard let userInfo else { return nil }
    var arguments: [String: Any] = [:]
    for (key, value) in userInfo {
      guard let key = key as? String else { continue }
      arguments[key] = value
    }
    self.init(arguments: arguments)
  }

  var dictionary: [String: Any] {
    var result: [String: Any] = [
      "version": Self.version,
      "activityId": activityID,
      "accountUserId": accountUserID,
      "chatId": chatID,
    ]
    if let messageID {
      result["messageId"] = messageID
    }
    return result
  }

  func matches(arguments: [String: Any]) -> Bool {
    Self.integer(arguments["version"]) == Int64(Self.version)
      && Self.integer(arguments["accountUserId"]) == accountUserID
      && Self.integer(arguments["chatId"]) == chatID
  }

  private static func integer(_ value: Any?) -> Int64? {
    guard let number = value as? NSNumber else { return nil }
    if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
    let double = number.doubleValue
    guard double.isFinite, double.rounded() == double else { return nil }
    return number.int64Value
  }
}

private enum HandoffStreamError: Error {
  case connection
  case responseTooLarge
  case timedOut
}

private final class HandoffStreamReader: NSObject, StreamDelegate {
  typealias Completion = (HandoffStreamReader, Result<Data, Error>) -> Void

  private let input: InputStream
  private let output: OutputStream
  private let completion: Completion
  private var buffer = Data()
  private var timer: Timer?
  private var finished = false

  init(input: InputStream, output: OutputStream, completion: @escaping Completion) {
    self.input = input
    self.output = output
    self.completion = completion
  }

  func start() {
    input.delegate = self
    output.delegate = self
    input.schedule(in: .main, forMode: .common)
    output.schedule(in: .main, forMode: .common)
    input.open()
    output.open()
    timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
      self?.finish(.failure(HandoffStreamError.timedOut))
    }
  }

  func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
    switch eventCode {
    case .hasBytesAvailable:
      readAvailableBytes()
    case .errorOccurred:
      finish(.failure(aStream.streamError ?? HandoffStreamError.connection))
    case .endEncountered where aStream === input:
      finish(.failure(HandoffStreamError.connection))
    default:
      break
    }
  }

  private func readAvailableBytes() {
    var bytes = [UInt8](repeating: 0, count: 1024)
    while input.hasBytesAvailable && !finished {
      let count = input.read(&bytes, maxLength: bytes.count)
      if count < 0 {
        finish(.failure(input.streamError ?? HandoffStreamError.connection))
        return
      }
      if count == 0 { return }
      buffer.append(contentsOf: bytes.prefix(count))
      if buffer.count > 8 * 1024 {
        finish(.failure(HandoffStreamError.responseTooLarge))
        return
      }
      if let newline = buffer.firstIndex(of: 0x0A) {
        finish(.success(Data(buffer[..<newline])))
        return
      }
    }
  }

  private func finish(_ result: Result<Data, Error>) {
    guard !finished else { return }
    finished = true
    timer?.invalidate()
    input.close()
    output.close()
    input.remove(from: .main, forMode: .common)
    output.remove(from: .main, forMode: .common)
    completion(self, result)
  }
}

private final class HandoffStreamWriter: NSObject, StreamDelegate {
  typealias Completion = (HandoffStreamWriter) -> Void

  private let input: InputStream
  private let output: OutputStream
  private let data: Data
  private let completion: Completion
  private var offset = 0
  private var timer: Timer?
  private var finished = false

  init(
    input: InputStream,
    output: OutputStream,
    data: Data,
    completion: @escaping Completion
  ) {
    self.input = input
    self.output = output
    self.data = data
    self.completion = completion
  }

  func start() {
    input.delegate = self
    output.delegate = self
    input.schedule(in: .main, forMode: .common)
    output.schedule(in: .main, forMode: .common)
    input.open()
    output.open()
    timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
      self?.finish()
    }
  }

  func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
    switch eventCode {
    case .hasSpaceAvailable where aStream === output:
      writeAvailableBytes()
    case .errorOccurred, .endEncountered:
      finish()
    default:
      break
    }
  }

  private func writeAvailableBytes() {
    guard !finished, offset < data.count else {
      finish()
      return
    }
    let written = data.withUnsafeBytes { rawBuffer -> Int in
      guard let baseAddress = rawBuffer.baseAddress else { return -1 }
      let start = baseAddress.assumingMemoryBound(to: UInt8.self).advanced(by: offset)
      return output.write(start, maxLength: data.count - offset)
    }
    if written <= 0 {
      if written < 0 { finish() }
      return
    }
    offset += written
    if offset == data.count { finish() }
  }

  private func finish() {
    guard !finished else { return }
    finished = true
    timer?.invalidate()
    input.close()
    output.close()
    input.remove(from: .main, forMode: .common)
    output.remove(from: .main, forMode: .common)
    completion(self)
  }
}
