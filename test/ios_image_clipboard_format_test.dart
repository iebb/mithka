import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS image clipboard rejects non-WebP RIFF payloads', () async {
    final source = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final branch = RegExp(
      r'      if call.method == "writeImage" \{([\s\S]*?)\n      \}\n      guard call.method == "readImage"',
    ).firstMatch(source)?.group(1);
    expect(branch, isNotNull);
    // Execute the production handler body. The pasteboard is a recorder,
    // not the system clipboard, and every payload is a synthetic header.
    final script =
        '''
import Foundation
struct FlutterStandardTypedData { let data: Data }
struct Call { let arguments: Any? }
final class UIPasteboard {
  static let general = UIPasteboard()
  var lastType: String?
  func setData(_ data: Data, forPasteboardType type: String) {
    lastType = type
  }
}
func handle(_ call: Call, result: (Bool) -> Void) {
$branch
}
func classify(_ bytes: [UInt8]) -> (Bool, String?) {
  UIPasteboard.general.lastType = nil
  var accepted = false
  handle(Call(arguments: FlutterStandardTypedData(data: Data(bytes))),
         result: { value in accepted = value })
  return (accepted, UIPasteboard.general.lastType)
}
func verify(_ condition: Bool, _ message: String = "format mismatch") {
  if !condition { print(message); exit(1) }
}
verify(classify([0x89, 0x50, 0x4e, 0x47]).1 == "public.png")
verify(classify([0x47, 0x49, 0x46, 0x38]).1 == "com.compuserve.gif")
verify(classify([0xff, 0xd8, 0xff]).1 == "public.jpeg")
verify(classify([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0,
                       0x57, 0x45, 0x42, 0x50]).1 == "org.webmproject.webp")
verify(!classify([0x52, 0x49, 0x46, 0x46]).0,
             "a truncated RIFF header is not a WebP image")
verify(!classify([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0,
                        0x57, 0x41, 0x56, 0x45]).0,
             "RIFF/WAVE audio is not a WebP image")
verify(!classify([]).0)
verify(!classify([1, 2, 3, 4]).0)
print("native clipboard format boundaries passed")
''';
    final process = await Process.start('xcrun', ['swift', '-']);
    final stdout = process.stdout.transform(utf8.decoder).join();
    final stderr = process.stderr.transform(utf8.decoder).join();
    process.stdin.write(script);
    await process.stdin.close();
    final code = await process.exitCode;
    expect(code, 0, reason: '${await stdout}\n${await stderr}');
  }, skip: !Platform.isMacOS);
}
