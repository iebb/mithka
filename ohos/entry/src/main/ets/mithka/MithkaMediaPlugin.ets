//
//  MithkaMediaPlugin.ets
//
//  HarmonyOS media bridge for the features whose pub.dev plugins have no
//  compatible OHOS port: photo/video picking (photo_manager, image_picker),
//  camera capture (camera, image_picker), voice-note recording and playback
//  (flutter_sound) and the microphone permission (permission_handler).
//
//  Picking and capture go through the system pickers, which grant access to
//  exactly what the user chose and need no permission. Every chosen item is
//  copied into the app cache so Dart only ever sees ordinary file paths.
//  Recording uses AVRecorder (AAC in an M4A container), which needs
//  ohos.permission.MICROPHONE. Playback gives each Dart player its own
//  AVPlayer; Dart polls its position and whether it reached the end.
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
import { audio } from '@kit.AudioKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { camera, cameraPicker } from '@kit.CameraKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { media } from '@kit.MediaKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';

const CHANNEL: string = 'mithka/ohos_media';
const MICROPHONE: Permissions = 'ohos.permission.MICROPHONE';

/// AVPlayer's discrete rates, nearest of which serves a requested speed.
const SPEED_VALUES: Array<number> = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2];
const SPEED_MODES: Array<media.PlaybackSpeed> = [
  media.PlaybackSpeed.SPEED_FORWARD_0_50_X,
  media.PlaybackSpeed.SPEED_FORWARD_0_75_X,
  media.PlaybackSpeed.SPEED_FORWARD_1_00_X,
  media.PlaybackSpeed.SPEED_FORWARD_1_25_X,
  media.PlaybackSpeed.SPEED_FORWARD_1_50_X,
  media.PlaybackSpeed.SPEED_FORWARD_1_75_X,
  media.PlaybackSpeed.SPEED_FORWARD_2_00_X,
];

/// One Dart player: its AVPlayer while a file is loaded, plus the volume and
/// speed that carry across starts.
class PlayerSlot {
  player: media.AVPlayer | null = null;
  file: fs.File | null = null;
  volume: number = 1;
  speed: number = 1;
  /// Playback reached the end, or failed and will not continue.
  ended: boolean = false;
}

export default class MithkaMediaPlugin implements FlutterPlugin, MethodCallHandler, AbilityAware {
  private channel: MethodChannel | null = null;
  private context: common.UIAbilityContext | null = null;
  private recorder: media.AVRecorder | null = null;
  private recordFile: fs.File | null = null;
  private recordPath: string | null = null;
  private players: Map<number, PlayerSlot> = new Map();

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
    for (const id of Array.from(this.players.keys())) {
      this.releasePlayer(id);
    }
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
      case 'playerStart':
        return this.startPlayer(call.argument('id') as number, call.argument('path') as string);
      case 'playerPause':
        await this.pausePlayer(call.argument('id') as number);
        return null;
      case 'playerResume':
        await this.resumePlayer(call.argument('id') as number);
        return null;
      case 'playerSeek':
        await this.seekPlayer(call.argument('id') as number, call.argument('position') as number);
        return null;
      case 'playerSetVolume':
        await this.setPlayerVolume(call.argument('id') as number, call.argument('volume') as number);
        return null;
      case 'playerSetSpeed':
        this.setPlayerSpeed(call.argument('id') as number, call.argument('speed') as number);
        return null;
      case 'playerProgress':
        return this.playerProgress(call.argument('id') as number);
      case 'playerStop':
        await this.stopPlayer(call.argument('id') as number);
        return null;
      case 'playerRelease':
        await this.releasePlayer(call.argument('id') as number);
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

  private slot(id: number): PlayerSlot {
    let slot = this.players.get(id);
    if (slot === undefined) {
      slot = new PlayerSlot();
      this.players.set(id, slot);
    }
    return slot;
  }

  private static isLoaded(player: media.AVPlayer): boolean {
    const state = player.state;
    return state === 'prepared' || state === 'playing' || state === 'paused' || state === 'completed';
  }

  private static playbackSpeed(speed: number): media.PlaybackSpeed {
    let best = 0;
    for (let i = 1; i < SPEED_VALUES.length; i++) {
      if (Math.abs(SPEED_VALUES[i] - speed) < Math.abs(SPEED_VALUES[best] - speed)) best = i;
    }
    return SPEED_MODES[best];
  }

  /// Loads [path] into a fresh AVPlayer and starts it; returns the duration
  /// in ms.
  private async startPlayer(id: number, path: string): Promise<number> {
    const slot = this.slot(id);
    await this.unloadPlayer(slot);
    const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    slot.file = file;
    slot.ended = false;
    try {
      const player = await media.createAVPlayer();
      slot.player = player;
      await new Promise<void>((resolve: () => void, reject: (error: Error) => void) => {
        player.on('stateChange', (state: string) => {
          if (state === 'initialized') {
            player.audioRendererInfo = {
              usage: audio.StreamUsage.STREAM_USAGE_VOICE_MESSAGE,
              rendererFlags: 0,
            };
            player.prepare().catch((error: BusinessError) => reject(new Error(error.message)));
          } else if (state === 'prepared') {
            resolve();
          } else if (state === 'completed') {
            slot.ended = true;
          }
        });
        player.on('error', (error: BusinessError) => {
          slot.ended = true;
          reject(new Error(error.message));
        });
        player.fdSrc = { fd: file.fd };
      });
      if (slot.volume !== 1) player.setVolume(slot.volume);
      if (slot.speed !== 1) player.setSpeed(MithkaMediaPlugin.playbackSpeed(slot.speed));
      await player.play();
      return player.duration;
    } catch (error) {
      await this.unloadPlayer(slot);
      throw error as Error;
    }
  }

  private async pausePlayer(id: number): Promise<void> {
    const player = this.players.get(id)?.player;
    if (player != null && player.state === 'playing') await player.pause();
  }

  private async resumePlayer(id: number): Promise<void> {
    const slot = this.players.get(id);
    const player = slot?.player;
    if (slot == null || player == null || !MithkaMediaPlugin.isLoaded(player)) return;
    if (player.state === 'playing') return;
    slot.ended = false;
    await player.play();
  }

  private async seekPlayer(id: number, position: number): Promise<void> {
    const slot = this.players.get(id);
    const player = slot?.player;
    if (slot == null || player == null || !MithkaMediaPlugin.isLoaded(player)) return;
    const target = Math.max(0, Math.min(Math.floor(position), player.duration));
    await new Promise<void>((resolve: () => void) => {
      const done = (): void => {
        player.off('seekDone');
        resolve();
      };
      player.on('seekDone', done);
      player.seek(target, media.SeekMode.SEEK_CLOSEST);
      // A seek that never reports back must not wedge the Dart player lock.
      setTimeout(done, 1000);
    });
  }

  private async setPlayerVolume(id: number, volume: number): Promise<void> {
    const slot = this.slot(id);
    slot.volume = Math.max(0, Math.min(1, volume));
    const player = slot.player;
    if (player != null && MithkaMediaPlugin.isLoaded(player)) player.setVolume(slot.volume);
  }

  private setPlayerSpeed(id: number, speed: number): void {
    const slot = this.slot(id);
    slot.speed = speed;
    const player = slot.player;
    if (player != null && MithkaMediaPlugin.isLoaded(player)) {
      player.setSpeed(MithkaMediaPlugin.playbackSpeed(speed));
    }
  }

  private playerProgress(id: number): Map<string, Object> {
    const slot = this.players.get(id);
    const player = slot?.player;
    const result: Map<string, Object> = new Map();
    if (slot == null || player == null) {
      result.set('position', 0);
      result.set('duration', 0);
      result.set('completed', true);
      return result;
    }
    const duration = Math.max(0, player.duration);
    const ended = slot.ended || player.state === 'completed' || player.state === 'error';
    result.set('position', ended ? duration : Math.max(0, player.currentTime));
    result.set('duration', duration);
    result.set('completed', ended);
    return result;
  }

  private async stopPlayer(id: number): Promise<void> {
    const slot = this.players.get(id);
    if (slot != null) await this.unloadPlayer(slot);
  }

  private async releasePlayer(id: number): Promise<void> {
    const slot = this.players.get(id);
    this.players.delete(id);
    if (slot != null) await this.unloadPlayer(slot);
  }

  /// Frees the slot's AVPlayer and file; volume and speed stay.
  private async unloadPlayer(slot: PlayerSlot): Promise<void> {
    const player = slot.player;
    slot.player = null;
    slot.ended = false;
    if (player != null) {
      try {
        player.off('stateChange');
        player.off('error');
        await player.release();
      } catch (_) {
      }
    }
    const file = slot.file;
    slot.file = null;
    if (file != null) {
      try {
        fs.closeSync(file);
      } catch (_) {
      }
    }
  }
}
