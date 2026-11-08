//
//  MithkaMediaPlugin.ets
//
//  HarmonyOS media bridge for the features whose pub.dev plugins have no
//  compatible OHOS port: photo/video picking (photo_manager, image_picker),
//  camera capture (camera, image_picker), voice-note recording
//  (flutter_sound) and the microphone permission (permission_handler).
//
//  Picking and capture go through the system pickers, which grant access to
//  exactly what the user chose and need no permission. Every chosen item is
//  copied into the app cache so Dart only ever sees ordinary file paths.
//  Recording uses AVRecorder (AAC in an M4A container), which needs
//  ohos.permission.MICROPHONE.
//

import {
  AbilityAware,
  AbilityPluginBinding,
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
} from '@ohos/flutter_ohos';
import { abilityAccessCtrl, bundleManager, common, Permissions, Want } from '@kit.AbilityKit';
import { camera, cameraPicker } from '@kit.CameraKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { media } from '@kit.MediaKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';

const CHANNEL: string = 'mithka/ohos_media';
const MICROPHONE: Permissions = 'ohos.permission.MICROPHONE';

export default class MithkaMediaPlugin implements FlutterPlugin, MethodCallHandler, AbilityAware {
  private channel: MethodChannel | null = null;
  private context: common.UIAbilityContext | null = null;
  private recorder: media.AVRecorder | null = null;
  private recordFile: fs.File | null = null;
  private recordPath: string | null = null;

  getUniqueClassName(): string {
    return 'MithkaMediaPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL);
    this.channel.setMethodCallHandler(this);
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
    this.releaseRecorder(true);
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.context = binding.getAbility().context;
  }

  onDetachedFromAbility(): void {
    this.context = null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    this.handle(call).then((value: Object | null) => {
      result.success(value);
    }).catch((error: Error) => {
      result.error('ohos_media', `${call.method}: ${error?.message ?? error}`, null);
    });
  }

  private async handle(call: MethodCall): Promise<Object | null> {
    switch (call.method) {
      case 'pickMedia':
        return this.pickMedia(call.argument('kind') as string, call.argument('maxCount') as number);
      case 'capture':
        return this.capture(call.argument('allowPhoto') as boolean, call.argument('allowVideo') as boolean);
      case 'microphoneStatus':
        return this.microphoneStatus();
      case 'requestMicrophone':
        return this.requestMicrophone();
      case 'openAppSettings':
        return this.openAppSettings();
      case 'recorderStart':
        await this.startRecorder(call.argument('path') as string, call.argument('sampleRate') as number,
          call.argument('bitRate') as number, call.argument('numChannels') as number);
        return null;
      case 'recorderPause':
        await this.requireRecorder().pause();
        return null;
      case 'recorderResume':
        await this.requireRecorder().resume();
        return null;
      case 'recorderStop':
        return this.stopRecorder();
      case 'recorderAmplitude':
        return this.recorder == null ? 0 : await this.recorder.getAudioCapturerMaxAmplitude();
      case 'recorderRelease':
        await this.releaseRecorder(true);
        return null;
      default:
        throw new Error('not implemented');
    }
  }

  private requireContext(): common.UIAbilityContext {
    if (this.context == null) throw new Error('no foreground ability');
    return this.context;
  }

  private requireRecorder(): media.AVRecorder {
    if (this.recorder == null) throw new Error('recorder not started');
    return this.recorder;
  }

  private cacheDir(): string {
    const dir = `${this.requireContext().cacheDir}/ohos_media`;
    if (!fs.accessSync(dir)) fs.mkdirSync(dir, true);
    return dir;
  }

  private uniqueName(): string {
    return `${Date.now()}_${Math.floor(Math.random() * 1000000)}`;
  }

  /// Copies a picker-granted URI into the cache, keeping its file name.
  private copyToCache(uri: string): string {
    const segments = uri.split('/');
    const name = segments[segments.length - 1] || 'media';
    const dest = `${this.cacheDir()}/${this.uniqueName()}_${name}`;
    const source = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    try {
      fs.copyFileSync(source.fd, dest);
    } finally {
      fs.closeSync(source);
    }
    return dest;
  }

  private async pickMedia(kind: string, maxCount: number): Promise<Array<string>> {
    const options = new photoAccessHelper.PhotoSelectOptions();
    options.MIMEType = kind === 'image' ? photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE :
      kind === 'video' ? photoAccessHelper.PhotoViewMIMETypes.VIDEO_TYPE :
      photoAccessHelper.PhotoViewMIMETypes.IMAGE_VIDEO_TYPE;
    options.maxSelectNumber = Math.max(1, Math.min(500, Math.floor(maxCount)));
    const picker = new photoAccessHelper.PhotoViewPicker();
    const selection = await picker.select(options);
    const paths: Array<string> = [];
    for (const uri of selection.photoUris ?? []) {
      paths.push(this.copyToCache(uri));
    }
    return paths;
  }

  /// Runs the system camera; returns the capture's cache path, or null when
  /// the user backs out.
  private async capture(allowPhoto: boolean, allowVideo: boolean): Promise<string | null> {
    const types: Array<cameraPicker.PickerMediaType> = [];
    if (allowPhoto) types.push(cameraPicker.PickerMediaType.PHOTO);
    if (allowVideo) types.push(cameraPicker.PickerMediaType.VIDEO);
    if (types.length === 0) types.push(cameraPicker.PickerMediaType.PHOTO);
    // The camera writes into this file; an untouched file is discarded.
    const path = `${this.cacheDir()}/capture_${this.uniqueName()}${allowPhoto ? '.jpg' : '.mp4'}`;
    fs.closeSync(fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE));
    const profile: cameraPicker.PickerProfile = {
      cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK,
      saveUri: fileUri.getUriFromPath(path),
    };
    const picked = await cameraPicker.pick(this.requireContext(), types, profile);
    if (picked.resultCode !== 0 || fs.statSync(path).size === 0) {
      fs.unlinkSync(path);
      return null;
    }
    if (picked.mediaType === cameraPicker.PickerMediaType.VIDEO && path.endsWith('.jpg')) {
      const video = path.substring(0, path.length - 4) + '.mp4';
      fs.renameSync(path, video);
      return video;
    }
    return path;
  }

  private selfTokenId(): number {
    const info = bundleManager.getBundleInfoForSelfSync(
      bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
    return info.appInfo.accessTokenId;
  }

  /// 'granted' or 'denied': a token check cannot tell whether the dialog
  /// would still appear; requestMicrophone answers that.
  private microphoneStatus(): string {
    const manager = abilityAccessCtrl.createAtManager();
    const status = manager.checkAccessTokenSync(this.selfTokenId(), MICROPHONE);
    return status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED ? 'granted' : 'denied';
  }

  /// 'granted', 'denied', or 'permanentlyDenied' when the system no longer
  /// shows the dialog and only Settings can grant it.
  private async requestMicrophone(): Promise<string> {
    const manager = abilityAccessCtrl.createAtManager();
    const answer = await manager.requestPermissionsFromUser(this.requireContext(), [MICROPHONE]);
    if (answer.authResults[0] === 0) return 'granted';
    const shown = answer.dialogShownResults;
    return shown != null && shown[0] === false ? 'permanentlyDenied' : 'denied';
  }

  private async openAppSettings(): Promise<boolean> {
    const context = this.requireContext();
    const want: Want = {
      bundleName: 'com.huawei.hmos.settings',
      abilityName: 'com.huawei.hmos.settings.MainAbility',
      uri: 'application_info_entry',
      parameters: { pushParams: context.abilityInfo.bundleName },
    };
    await context.startAbility(want);
    return true;
  }

  private async startRecorder(path: string, sampleRate: number, bitRate: number,
    numChannels: number): Promise<void> {
    await this.releaseRecorder(true);
    const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    this.recordFile = file;
    this.recordPath = path;
    try {
      const recorder = await media.createAVRecorder();
      this.recorder = recorder;
      const config: media.AVRecorderConfig = {
        audioSourceType: media.AudioSourceType.AUDIO_SOURCE_TYPE_MIC,
        profile: {
          audioBitrate: bitRate > 0 ? bitRate : 32000,
          audioChannels: numChannels > 0 ? numChannels : 1,
          audioCodec: media.CodecMimeType.AUDIO_AAC,
          audioSampleRate: sampleRate > 0 ? sampleRate : 48000,
          fileFormat: media.ContainerFormatType.CFT_MPEG_4A,
        },
        url: `fd://${file.fd}`,
      };
      await recorder.prepare(config);
      await recorder.start();
    } catch (error) {
      await this.releaseRecorder(true);
      throw error as Error;
    }
  }

  private async stopRecorder(): Promise<string | null> {
    const path = this.recordPath;
    if (this.recorder != null) {
      try {
        await this.recorder.stop();
      } finally {
        await this.releaseRecorder(false);
      }
    }
    return path;
  }

  /// Frees the recorder and its file descriptor; [discard] also deletes an
  /// unfinished recording.
  private async releaseRecorder(discard: boolean): Promise<void> {
    const recorder = this.recorder;
    this.recorder = null;
    if (recorder != null) {
      try {
        await recorder.release();
      } catch (_) {
      }
    }
    const file = this.recordFile;
    this.recordFile = null;
    if (file != null) {
      try {
        fs.closeSync(file);
      } catch (_) {
      }
    }
    const path = this.recordPath;
    this.recordPath = null;
    if (discard && path != null && recorder != null) {
      try {
        fs.unlinkSync(path);
      } catch (_) {
      }
    }
  }
}
