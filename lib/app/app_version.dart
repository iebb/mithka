import 'package:package_info_plus/package_info_plus.dart';

class AppVersion {
  const AppVersion({
    required this.version,
    required this.buildNumber,
    required this.commit,
  });

  static const _commit = String.fromEnvironment('GIT_COMMIT');
  static const _ciBuildStamp = String.fromEnvironment('CI_BUILD_STAMP');

  final String version;
  final String buildNumber;
  final String commit;

  String get display {
    final parts = <String>[version];
    if (buildNumber.isNotEmpty) parts.add(buildNumber);
    if (commit.isNotEmpty) parts.add(commit);
    return parts.join('+');
  }

  Map<String, Object> get analyticsParameters => {
    'app_display_version': display,
    'app_version_name': version,
    'app_build_number': buildNumber,
    'git_commit': commit,
  };

  static Future<AppVersion> load() async {
    final info = await PackageInfo.fromPlatform();
    return AppVersion(
      version: info.version,
      buildNumber: _ciBuildStamp.isEmpty ? info.buildNumber : _ciBuildStamp,
      commit: _commit.isEmpty ? 'local' : _commit,
    );
  }
}
