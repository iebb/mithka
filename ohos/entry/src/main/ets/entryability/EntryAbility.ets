
import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import MithkaMediaPlugin from '../mithka/MithkaMediaPlugin';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';

export default class EntryAbility extends FlutterAbility {
  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    // App-owned bridge for pickers, capture, recording and the microphone
    // permission; see lib/platform/ohos_media_bridge.dart.
    flutterEngine.getPlugins()?.add(new MithkaMediaPlugin())
  }
}
