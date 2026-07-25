import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/diagnostic_breadcrumbs.dart';

void main() {
  test('successful getMessage requests do not create breadcrumbs', () {
    expect(
      DiagnosticBreadcrumbs.shouldRecordTdlibRequest(
        requestType: 'getMessage',
        failed: false,
      ),
      isFalse,
    );
    expect(
      DiagnosticBreadcrumbs.shouldRecordTdlibRequest(
        requestType: 'getMessage',
        failed: true,
      ),
      isTrue,
    );
  });

  test('other selected operations retain successful breadcrumbs', () {
    expect(
      DiagnosticBreadcrumbs.shouldRecordTdlibRequest(
        requestType: 'sendMessage',
        failed: false,
      ),
      isTrue,
    );
    expect(
      DiagnosticBreadcrumbs.shouldRecordTdlibRequest(
        requestType: 'downloadFile',
        failed: false,
      ),
      isFalse,
    );
  });
}
