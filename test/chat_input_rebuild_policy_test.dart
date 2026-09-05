import 'dart:io';

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

  test('every view-model value the composer draws is compared for change', () {
    // Suppressing revision-only rebuilds while focused means a view-model
    // value the composer renders stops updating unless _syncFromVm compares it
    // itself. The auto-delete indicator stayed on screen after its timer was
    // cleared because it was missing from that comparison; these are the rest
    // of the values read from `vm` in the same build.
    final source = File('lib/chat/chat_input_bar.dart').readAsStringSync();
    final snapshot = source.substring(
      source.indexOf('_ComposerVmState get _renderedVmState'),
      source.indexOf(
        ';',
        source.indexOf('_ComposerVmState get _renderedVmState'),
      ),
    );
    for (final field in const [
      'vm.messageAutoDeleteTime',
      'vm.selectedMessageSender',
      'vm.canChooseMessageSender',
      'vm.peerIsBot',
    ]) {
      expect(
        snapshot,
        contains(field),
        reason:
            '$field is rendered by the composer, so a change in it has to '
            'survive the focused-rebuild gate',
      );
    }
  });
}
