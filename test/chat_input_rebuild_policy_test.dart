import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_input_bar.dart';

void main() {
  test('does not rebuild the focused composer for revision-only updates', () {
    expect(
      shouldRebuildComposerForVmUpdate(
        revisionChanged: true,
        localChanged: false,
        hasFocus: true,
      ),
      isFalse,
    );
  });

  test('still refreshes unfocused and locally changed composer state', () {
    expect(
      shouldRebuildComposerForVmUpdate(
        revisionChanged: true,
        localChanged: false,
        hasFocus: false,
      ),
      isTrue,
    );
    expect(
      shouldRebuildComposerForVmUpdate(
        revisionChanged: false,
        localChanged: true,
        hasFocus: true,
      ),
      isTrue,
    );
  });
}
