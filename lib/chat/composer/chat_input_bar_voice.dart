part of 'chat_input_bar.dart';

extension _ChatInputBarVoice on _ChatInputBarState {
  void _toggleVoice() {
    _focus.unfocus();
    final opening = _panel != _Panel.voice;
    if (opening) {
      _voiceUsesDesktopRecorder = _usesNativeDesktopComposer(context);
    }
    _setPanel(opening ? _Panel.voice : _Panel.none);
    if (opening) {
      // A new opening is a new attempt: whatever refused the microphone last
      // time can be retried, and its prompt is due once for this opening.
      _recorderPreparationFailure = null;
      final testingHook = widget.onVoicePanelOpenedForTesting;
      if (testingHook != null) {
        testingHook();
      } else {
        // A preparation nobody waits on must still handle its failure: the
        // open reports it once, and the flag keeps every press in this opening
        // from reporting the same cause again.
        unawaited(
          _prepareRecorder().catchError((Object error) {
            _recorderPreparationFailure = error;
          }),
        );
      }
      if (_usesNativeDesktopComposer(context)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _panel == _Panel.voice) {
            _desktopVoiceFocus.requestFocus();
          }
        });
      }
    }
  }

  Future<void> _prepareRecorder() async {
    if (_voiceUsesDesktopRecorder) {
      await _prepareDesktopRecorder();
      return;
    }
    if (_recorder != null) return;
    // Reopening the panel is the retry. Until then, one failed preparation
    // answers every press: the session cannot be claimed either way, and a
    // second attempt would report the same failure twice for one tap.
    final failed = _recorderPreparationFailure;
    if (failed != null) {
      throw _ReportedCaptureFailure(failed);
    }
    final pending = _recorderPreparation;
    if (pending != null) return pending;
    late final Future<void> preparation;
    preparation = _createMobileRecorder().whenComplete(() {
      if (identical(_recorderPreparation, preparation)) {
        _recorderPreparation = null;
      }
    });
    _recorderPreparation = preparation;
    await preparation;
    final failure = _recorderPreparationFailure;
    if (failure != null) throw _ReportedCaptureFailure(failure);
  }

  Future<void> _createMobileRecorder() async {
    FlutterSoundRecorder? recorder;
    try {
      final permission = widget.microphonePermissionForTesting;
      var status = permission != null
          ? await permission()
          : await Permission.microphone.status;
      if (permission == null &&
          !status.isGranted &&
          !status.isPermanentlyDenied &&
          !status.isRestricted) {
        status = await Permission.microphone.request();
      }
      if (_voiceDisposed || !mounted) return;
      if (!status.isGranted) {
        // The open panel explains the denial inline and offers Settings; it
        // never opens system Settings without the user's press. `restricted`
        // is a system-wide microphone lock the app cannot prompt through, so
        // it takes the same settings route as a permanently denied answer.
        if (_showsMobileVoicePanel) {
          _setVoiceInlineError(
            status.isPermanentlyDenied || status.isRestricted
                ? _VoiceInlineError.microphoneSettings
                : _VoiceInlineError.microphoneRequired,
          );
        } else {
          showToast(
            context,
            AppStrings.t(
              status.isPermanentlyDenied || status.isRestricted
                  ? AppStringKeys.composerMicrophonePermissionSettings
                  : AppStringKeys.composerMicrophonePermissionRequired,
            ),
          );
        }
        widget.onRecordingIssueForTesting?.call('permission', status);
        // Any refusal answers this opening. A `request()` on an already-refused
        // permission never shows a sheet, so pressing again would only repeat
        // the same notice; reopening the panel or returning from Settings is
        // the retry.
        _recorderPreparationFailure ??= _ReportedCaptureFailure(status.name);
        return;
      }
      recorder =
          widget.mobileVoiceRecorderFactory?.call() ??
          FlutterSoundRecorder(logLevel: Level.warning);
      await recorder.openRecorder();
      await recorder.setSubscriptionDuration(const Duration(milliseconds: 100));
      if (_voiceDisposed || !mounted) {
        await recorder.closeRecorder();
        return;
      }
      _updateState(() => _recorder = recorder);
    } catch (error) {
      await _releaseCaptureSession();
      try {
        await recorder?.closeRecorder();
      } catch (_) {}
      _recorderPreparationFailure = error;
      _showRecordingError(error: error, stage: 'open');
    }
  }

  Future<void> _prepareCaptureSession() async {
    if (_captureSession != null) return;
    if (_voiceUsesDesktopRecorder) return;
    final session =
        widget.voiceRecordingSession ??
        (composerUsesMobileVoiceSession(Theme.of(context).platform)
            ? const SharedVoiceRecordingAudioSession()
            : null);
    if (session == null) return;
    await session.prepareForCapture();
    _captureSession = session;
  }

  Future<void> _releaseCaptureSession() async {
    final session = _captureSession;
    if (session == null) return;
    _captureSession = null;
    try {
      await session.releaseAfterCapture();
    } catch (_) {}
  }

  Future<void> _openMicrophoneSettings() async {
    final open = widget.openAppSettingsForTesting ?? openAppSettings;
    try {
      await open();
    } catch (_) {}
  }

  Future<void> _prepareDesktopRecorder() async {
    if (_desktopRecorder != null) return;
    // The panel opening prepares once and every press waits on that same
    // preparation, so a refusal must answer the whole opening.
    final failed = _recorderPreparationFailure;
    if (failed != null) {
      throw _ReportedCaptureFailure(failed);
    }
    final pending = _desktopRecorderPreparation;
    if (pending != null) {
      await pending;
      return;
    }
    late final Future<void> preparation;
    preparation = _createDesktopRecorder().whenComplete(() {
      if (identical(_desktopRecorderPreparation, preparation)) {
        _desktopRecorderPreparation = null;
      }
    });
    _desktopRecorderPreparation = preparation;
    await preparation;
  }

  Future<void> _createDesktopRecorder() async {
    final recorder =
        widget.desktopVoiceRecorderFactory?.call() ??
        desktop_record.AudioRecorder();
    bool allowed;
    try {
      allowed = await recorder.hasPermission();
    } catch (error) {
      // A platform that cannot answer the permission query is not the same
      // failure as a denied microphone; keep the cause instead of reporting a
      // generic capture error.
      await recorder.dispose();
      _showRecordingError(error: error, stage: 'permission');
      return;
    }
    if (!allowed) {
      await recorder.dispose();
      if (!mounted) return;
      // `record` only shows the macOS prompt while the grant is undetermined.
      // Once refused, nothing in the app can ask again, so the settings page is
      // the user's only route - and the same refusal must not be re-reported on
      // every later press in this opening.
      _recorderPreparationFailure = const DesktopMicrophoneRefused();
      _showRecordingError(
        error: const DesktopMicrophoneRefused(),
        stage: 'permission',
      );
      unawaited(_openMicrophoneSettings());
      return;
    }
    if (_voiceDisposed || !mounted) {
      await recorder.dispose();
      return;
    }
    _updateState(() => _desktopRecorder = recorder);
  }

  Future<void> _beginVoiceRecording() {
    if (_voiceDisposed ||
        _voiceStop != null ||
        _recording ||
        _desktopVoiceDraft != null ||
        (_showsMobileVoicePanel && _composerAttachmentWaiting)) {
      return Future<void>.value();
    }
    final pending = _voiceStart;
    if (pending != null) return pending;
    _recordCancelled = false;
    _recordingPaused = false;
    _recordingLocked = false;
    _elapsed = 0;
    _recLevels.clear();
    _recTick.value = (elapsed: 0.0, levels: const <double>[]);
    _updateState(() => _startingRecording = true);
    late final Future<void> start;
    start =
        prepareDesktopVoiceRecording(
              prepare: _prepareRecorder,
              shouldStart: () => _canStartHeldRecording,
              start: _startRec,
            )
            .catchError((Object error) {
              // A preparation that failed while the panel opened was reported
              // then; every press in the same opening would otherwise repeat it.
              if (error is _ReportedCaptureFailure) {
                // The press cleared the inline row; a permission refusal in
                // this opening still has to stay visible, so re-arm it from
                // the remembered failure instead of leaving "hold to talk".
                _rearmReportedCaptureFailure(error.cause);
                return;
              }
              _showRecordingError(error: error, stage: 'begin');
            })
            .whenComplete(() {
              if (identical(_voiceStart, start)) _voiceStart = null;
              _startingRecording = false;
              if (mounted && !_voiceDisposed) _updateState(() {});
            });
    _voiceStart = start;
    return start;
  }

  void _showRecordingError({Object? error, String? stage, String? codec}) {
    widget.onRecordingIssueForTesting?.call(stage ?? 'unknown', error);
    if (mounted && !_voiceDisposed && _panel == _Panel.voice) {
      if (!_voiceUsesDesktopRecorder) {
        _setVoiceInlineError(_VoiceInlineError.failed);
        return;
      }
      showToast(context, AppStrings.t(AppStringKeys.composerRecordingFailed));
    }
    if (error != null) {
      DiagnosticBreadcrumbs.voiceRecordingFailed(
        stage: stage ?? 'unknown',
        error: error,
        codec: codec,
      );
    }
  }

  void _setVoiceInlineError(_VoiceInlineError error) {
    if (!mounted || _voiceDisposed || !_showsMobileVoicePanel) return;
    // A live recording keeps its status line; the failed action (pause or
    // resume) leaves the recording as it was, so only the haptic reports it.
    if (_recording) {
      unawaited(HapticFeedback.heavyImpact());
      return;
    }
    if (_voiceInlineError == error) return;
    _updateState(() => _voiceInlineError = error);
    unawaited(HapticFeedback.heavyImpact());
  }

  void _clearVoiceInlineError() {
    if (_voiceInlineError == _VoiceInlineError.none) return;
    _updateState(() => _voiceInlineError = _VoiceInlineError.none);
  }

  void _rearmReportedCaptureFailure(Object cause) {
    if (!mounted || _voiceDisposed || !_showsMobileVoicePanel) return;
    // The stored failure may be a bare status name or the wrapper
    // `_ReportedCaptureFailure` re-thrown by `_prepareRecorder`.
    var detail = cause;
    while (detail is _ReportedCaptureFailure) {
      detail = detail.cause;
    }
    final name = detail is PermissionStatus
        ? detail.name
        : detail is String
        ? detail
        : null;
    _updateState(() {
      _voiceInlineError = switch (name) {
        'permanentlyDenied' ||
        'restricted' => _VoiceInlineError.microphoneSettings,
        'denied' || 'notDetermined' => _VoiceInlineError.microphoneRequired,
        _ => _VoiceInlineError.failed,
      };
    });
  }

  Future<void> _startRec() async {
    if (_voiceUsesDesktopRecorder) {
      await _startDesktopRec();
      return;
    }
    final r = _recorder;
    if (r == null || _recording) return;
    // The shared session belongs to whatever audio would normally play, and a
    // playback category admits no input: the recorder would open on top of it
    // with no microphone route. Claim the capture category for exactly this
    // recording - the recorder itself stays open across recordings.
    await _prepareCaptureSession();
    if (_voiceDisposed || !mounted) return;
    final dir = await getTemporaryDirectory();
    // Apple's AAC encoder rejects anything below 32 kbps at 48 kHz, and
    // AVAudioRecorder then records nothing without reporting an error, so
    // AAC gets an explicit 32 kbps (the macOS recorder's setting). Opus keeps
    // the plugin's 16 kbps default.
    const candidates = [
      (Codec.opusOGG, 'ogg', 16000),
      (Codec.opusWebM, 'webm', 16000),
      (Codec.aacMP4, 'm4a', 32000),
      (Codec.aacADTS, 'aac', 32000),
    ];
    var started = false;
    // The recorder's own message never says which container failed, and every
    // attempt is discarded on the way to the next one; keep the first cause so
    // the failure the user sees is diagnosable.
    Object? firstFailure;
    String? firstFailureCodec;
    for (final (codec, extension, bitRate) in candidates) {
      if (!_canStartHeldRecording) return;
      try {
        if (!await r.isEncoderSupported(codec)) continue;
        if (!_canStartHeldRecording) return;
        final path =
            '${dir.path}/voice_${DateTime.now().microsecondsSinceEpoch}.$extension';
        _recPath = path;
        await r.startRecorder(
          toFile: path,
          codec: codec,
          sampleRate: 48000,
          bitRate: bitRate,
        );
        started = true;
        break;
      } catch (error) {
        firstFailure ??= error;
        firstFailureCodec ??= codec.name;
        // Some devices claim Opus support but fail when opening the encoder.
        // Close that attempt before trying the next supported container.
        try {
          await r.stopRecorder();
        } catch (_) {}
        final path = _recPath;
        _recPath = null;
        if (path != null) await _deleteTempFile(path);
      }
    }
    if (!started) {
      _showRecordingError(
        error: firstFailure,
        stage: 'start',
        codec: firstFailureCodec,
      );
      // No container opened: this recorder holds nothing, and the capture
      // session must go back to playback rather than stay on `playAndRecord`.
      await _releaseCaptureSession();
      return;
    }
    if (_voiceDisposed || !mounted) return;
    _updateState(() => _recording = true);
    unawaited(HapticFeedback.mediumImpact());
    await _recProgress?.cancel();
    final clock = VoiceRecordingClock();
    _recProgress = r.onProgress?.listen((event) {
      if (!mounted || _voiceDisposed || !_recording || _recordingPaused) return;
      clock.update(event.duration);
      _elapsed = clock.seconds;
      final level = event.decibels;
      if (level != null && level.isFinite) {
        _recLevels.add((level >= 0 ? level - 120 : level).clamp(-120.0, 0.0));
      }
      _recTick.value = (
        elapsed: _elapsed,
        levels: _recLevels.reversed
            .take(_ChatInputBarState._mobileMeterBars)
            .toList()
            .reversed
            .toList(),
      );
    });
    _recTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted || _voiceDisposed || !_recording) return;
      // Only here to move the clock until the recorder's own progress stream
      // reports; once it has, the timer has nothing left to do.
      if (clock.hasRecorderProgress) {
        timer.cancel();
        _recTimer = null;
        return;
      }
      clock.tick(const Duration(milliseconds: 100), paused: _recordingPaused);
      _elapsed = clock.seconds;
      _recTick.value = (elapsed: _elapsed, levels: _recTick.value.levels);
    });
  }

  Future<void> _startDesktopRec() async {
    final recorder = _desktopRecorder;
    if (recorder == null || _recording) return;
    final directory = await getTemporaryDirectory();
    if (!_canStartHeldRecording) return;
    final path =
        '${directory.path}/voice_${DateTime.now().microsecondsSinceEpoch}.m4a';
    _recPath = path;
    try {
      await recorder.start(
        const desktop_record.RecordConfig(
          sampleRate: 48000,
          numChannels: 1,
          bitRate: 32000,
        ),
        path: path,
      );
    } catch (error) {
      try {
        await recorder.cancel();
      } catch (_) {}
      await _deleteTempFile(path);
      _recPath = null;
      _showRecordingError(error: error, stage: 'start');
      return;
    }
    if (_voiceDisposed || !mounted) return;
    _updateState(() => _recording = true);
    await _desktopRecProgress?.cancel();
    _desktopRecProgress = recorder
        .onAmplitudeChanged(const Duration(milliseconds: 100))
        .listen((amplitude) {
          if (!mounted || _voiceDisposed || !_recording || _recordingPaused) {
            return;
          }
          final level = amplitude.current;
          if (level.isFinite) {
            _recLevels.add(level.clamp(-120.0, 0.0));
            _recTick.value = (
              elapsed: _elapsed,
              levels: _recLevels.reversed.take(120).toList().reversed.toList(),
            );
          }
        });
    _recTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted || _voiceDisposed || !_recording) return;
      if (_recordingPaused) return;
      _elapsed += 0.1;
      _recTick.value = (elapsed: _elapsed, levels: _recTick.value.levels);
    });
  }

  Future<void> _stopRec() {
    final pending = _voiceStop;
    if (pending != null) return pending;
    if (_voiceDisposed || !mounted) return Future<void>.value();
    _updateState(() => _stoppingRecording = true);
    late final Future<void> stop;
    stop = _finishVoiceRecording().whenComplete(() {
      if (identical(_voiceStop, stop)) _voiceStop = null;
      _stoppingRecording = false;
      if (mounted && !_voiceDisposed) _updateState(() {});
    });
    _voiceStop = stop;
    return stop;
  }

  Future<void> _finishVoiceRecording() async {
    // A release/cancel may arrive during permission or native startup. Wait
    // for that exact start, then finalize it once; never start another clip
    // or send twice while the previous stop is still asynchronous.
    await _voiceStart;
    // The capture session is released on every way out of this method. It was
    // claimed for exactly one recording; leaving it on `playAndRecord` would
    // hand the next track a category that changes how it plays, and holding it
    // through a failed start would keep other apps from taking audio back.
    try {
      await _finishMobileVoiceCapture();
    } finally {
      await _releaseCaptureSession();
    }
  }

  Future<void> _finishMobileVoiceCapture() async {
    if (_voiceDisposed || !_recording) return;
    final target = vm;
    final duration = _elapsed.round();
    final levels = List<double>.unmodifiable(_recLevels);
    final originalPath = _recPath;
    _recTimer?.cancel();
    _recTimer = null;
    await _recProgress?.cancel();
    _recProgress = null;
    await _desktopRecProgress?.cancel();
    _desktopRecProgress = null;
    _recording = false;
    _recordingPaused = false;
    _recordingLocked = false;
    _clearVoicePresses();
    if (mounted && !_voiceDisposed) _updateState(() {});
    String? recordedPath;
    try {
      recordedPath = _voiceUsesDesktopRecorder
          ? await _desktopRecorder?.stop()
          : await _recorder?.stopRecorder();
    } catch (_) {
      // A failed stop must still release the microphone before another hold.
      try {
        if (_voiceUsesDesktopRecorder) {
          await _desktopRecorder?.cancel();
        } else {
          final recorder = _recorder;
          _recorder = null;
          await recorder?.closeRecorder();
        }
      } catch (_) {}
    }
    // Capture is over the moment the recorder stops. Hand the session back
    // before the preview (which plays the clip through its own player) and
    // before any upload, so nothing keeps `playAndRecord` while the user is
    // trimming or while the file is in flight.
    await _releaseCaptureSession();
    final url = await _waitForRecordingFile(recordedPath);
    _recPath = null;
    final cancelled =
        _recordCancelled ||
        _voiceDisposed ||
        !mounted ||
        _panel != _Panel.voice ||
        !identical(target, vm) ||
        !_canSendVoiceNotes;
    if (cancelled || duration < 1 || url == null) {
      for (final path in {originalPath, recordedPath}.whereType<String>()) {
        await _deleteTempFile(path);
      }
      if (_voiceDisposed || !mounted) return;
      if (!cancelled && duration >= 1 && url == null) _showRecordingError();
      _resetRecordingMeter();
      return;
    }
    if (!mounted || _voiceDisposed) return;
    if (_voiceUsesDesktopRecorder) {
      _updateState(
        () => _desktopVoiceDraft = VoiceNoteDraft(
          path: url,
          duration: duration,
          waveform: encodeTelegramWaveform(levels),
          sendConfiguration: const MessageSendConfiguration(),
        ),
      );
      await _sendDesktopVoiceDraft();
    } else {
      // The draft is the preview: the panel closes, the keyboard stays down,
      // and the recording waits above the field until it is sent or deleted.
      if (_composerAttachmentWaiting) {
        await _deleteTempFile(url);
        if (_voiceDisposed || !mounted) return;
        _resetRecordingMeter();
        return;
      }
      _voiceDraft = ComposerVoiceDraft(
        path: url,
        duration: duration,
        levels: levels,
      );
      // The draft holds its own copy; the next recording starts from zero.
      _resetRecordingMeter();
      _setPanel(_Panel.none);
    }
  }

  Future<void> _sendDesktopVoiceDraft() async {
    final draft = _desktopVoiceDraft;
    if (draft == null || _sendingVoice || !_canSendVoiceNotes) return;
    final target = vm;
    _updateState(() => _sendingVoice = true);
    var sent = false;
    try {
      sent = await target.sendVoice(
        draft.path,
        draft.duration,
        waveform: draft.waveform,
        sendConfiguration: draft.sendConfiguration,
      );
    } catch (_) {}
    _sendingVoice = false;
    if (sent) {
      // TDLib still needs the file for its upload after accepting the send.
      _desktopVoiceDraft = null;
    } else if (_voiceDisposed || !mounted || !identical(target, vm)) {
      await _deleteTempFile(draft.path);
      _desktopVoiceDraft = null;
    }
    if (_voiceDisposed || !mounted || !identical(target, vm)) return;
    _updateState(() {});
    if (sent) {
      _finishPanelSend();
    } else {
      showToast(
        context,
        AppStrings.t(AppStringKeys.composerRecordingSendFailed),
      );
    }
  }

  void _discardDesktopVoiceDraft() {
    if (_sendingVoice) return;
    final draft = _desktopVoiceDraft;
    _desktopVoiceDraft = null;
    if (draft == null) return;
    unawaited(_deleteTempFile(draft.path));
    if (mounted && !_voiceDisposed) {
      _elapsed = 0;
      _recLevels.clear();
      _recTick.value = (elapsed: 0.0, levels: const <double>[]);
      _updateState(() {});
    }
  }

  void _discardVoiceDraft({bool rebuild = true}) {
    final draft = _voiceDraft;
    if (draft == null) return;
    _voiceDraft = null;
    // A send in flight still owns the file; it cleans up when it settles.
    if (!draft.sending) unawaited(_deleteTempFile(draft.path));
    draft.dispose();
    if (rebuild && mounted && !_voiceDisposed) {
      _updateState(() {});
      widget.onPanelGeometryChanged?.call();
    }
  }

  bool _voiceDraftIsCurrent(ComposerVoiceDraft draft, ChatViewModel target) =>
      mounted &&
      !_voiceDisposed &&
      identical(_voiceDraft, draft) &&
      identical(target, vm);

  Future<void> _sendVoiceDraft({
    MessageSendConfiguration sendConfiguration =
        const MessageSendConfiguration(),
  }) async {
    final draft = _voiceDraft;
    if (draft == null || draft.sending) return;
    final target = vm;
    if (!_canSendVoiceNotes) {
      // Voice messages stopped being allowed here (a restriction error or a
      // permission change): a retry says so on the card instead of nothing.
      unawaited(draft.pause());
      draft.markFailed();
      _updateState(() {});
      return;
    }
    draft.sending = true;
    _updateState(() {});
    unawaited(draft.pause());
    TrimmedVoiceNote? exported;
    var attempted = false;
    var sent = false;
    try {
      sent = await () async {
        final canAttemptSend = await target.prepareMessageSend();
        if (!mounted ||
            !canAttemptSend ||
            !_voiceDraftIsCurrent(draft, target)) {
          return false;
        }
        final (caption, entities) = _controller.toFormatted();
        final captionLimit = await target.messageCaptionLengthLimit();
        if (!mounted || !_voiceDraftIsCurrent(draft, target)) return false;
        if (telegramUtf8CharacterCount(caption.trim()) > captionLimit) {
          showToast(
            context,
            AppStrings.t(AppStringKeys.composerCaptionTooLong, {
              'value1': '$captionLimit',
            }),
          );
          return false;
        }
        if (target.requiresPaidMessage) {
          final ok = await _confirmPaidMessageSend();
          if (!ok || !_voiceDraftIsCurrent(draft, target)) return false;
        }
        attempted = true;
        final file = exported = await draft.export();
        if (!_voiceDraftIsCurrent(draft, target)) return false;
        return target.sendVoice(
          file.path,
          file.durationSeconds,
          waveform: encodeTelegramWaveform(draft.trimmedLevels()),
          caption: caption,
          captionEntities: entities,
          sendConfiguration: sendConfiguration,
          // The card's own error line reports a plain failure.
          reportGenericFailure: false,
        );
      }();
    } catch (error) {
      debugPrint('Failed to send the voice draft: $error');
    }
    final exportedPath = exported?.path;
    final trimmedCopy = exportedPath != null && exportedPath != draft.path
        ? exportedPath
        : null;
    if (sent) {
      // TDLib uploads the sent file after accepting the message, so only an
      // original that a trimmed copy replaced can go.
      if (trimmedCopy != null) unawaited(_deleteTempFile(draft.path));
      if (identical(_voiceDraft, draft)) _voiceDraft = null;
      draft.dispose();
    } else {
      if (trimmedCopy != null) unawaited(deleteExportedVoiceNote(trimmedCopy));
      if (!identical(_voiceDraft, draft)) {
        // The composer let go of the draft while it was sending.
        unawaited(_deleteTempFile(draft.path));
      } else if (attempted) {
        draft.markFailed();
      } else {
        draft.sending = false;
      }
    }
    if (!mounted || _voiceDisposed || !identical(target, vm)) return;
    _updateState(() {});
    if (sent) {
      widget.onPanelGeometryChanged?.call();
      _controller.clear();
      widget.onMessageSent();
    }
  }

  void _resetRecordingMeter() {
    _elapsed = 0;
    _recLevels.clear();
    _recTick.value = (elapsed: 0.0, levels: const <double>[]);
  }

  void _clearVoicePresses() {
    _desktopSpaceHeld = false;
    _desktopPointerHeld = false;
    _mobilePointerHeld = false;
    _voicePointerId = null;
    _lockedStopPointerId = null;
  }

  void _cancelVoiceRecording() {
    _clearVoicePresses();
    _recordCancelled = true;
    if (!_voiceDisposed &&
        (_recording || _voiceStart != null || _voiceStop != null)) {
      unawaited(_stopRec());
    }
  }

  Future<void> _disposeVoiceRecorders() async {
    try {
      await _voiceStart;
      await _voiceStop;
    } catch (_) {}
    try {
      await _recorder?.closeRecorder();
    } catch (_) {}
    try {
      await _desktopRecorder?.dispose();
    } catch (_) {}
    final path = _recPath;
    if (path != null) await _deleteTempFile(path);
    await _releaseCaptureSession();
    _discardDesktopVoiceDraft();
  }

  Future<void> _toggleRecPause() async {
    if (!_recording || _stoppingRecording || _changingRecordingPause) return;
    _changingRecordingPause = true;
    final paused = _recordingPaused;
    try {
      if (_voiceUsesDesktopRecorder) {
        if (paused) {
          await _desktopRecorder?.resume();
        } else {
          await _desktopRecorder?.pause();
        }
      } else if (paused) {
        await _recorder?.resumeRecorder();
      } else {
        await _recorder?.pauseRecorder();
      }
      if (mounted && !_voiceDisposed && _recording && !_stoppingRecording) {
        _updateState(() => _recordingPaused = !paused);
      }
    } catch (_) {
      _showRecordingError();
    } finally {
      _changingRecordingPause = false;
    }
  }

  void _cancelLockedRecording() {
    _cancelVoiceRecording();
  }

  KeyEventResult _handleDesktopVoiceKeyEvent(FocusNode node, KeyEvent event) {
    if (!_voiceUsesDesktopRecorder || _panel != _Panel.voice) {
      return KeyEventResult.ignored;
    }
    if (event is KeyRepeatEvent) {
      return event.logicalKey == LogicalKeyboardKey.space && _desktopSpaceHeld
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent && event is! KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    final isKeyDown = event is KeyDownEvent;
    final action = desktopVoiceMessageAction(
      isSpace: event.logicalKey == LogicalKeyboardKey.space,
      isEscape: event.logicalKey == LogicalKeyboardKey.escape,
      isKeyDown: isKeyDown,
      isRecording: _recording,
      spaceHeld: _desktopSpaceHeld,
      hasModifiers: keyboardModifiersPressed(),
    );
    switch (action) {
      case DesktopVoiceMessageAction.start:
        if (_voiceStop != null || _desktopVoiceDraft != null || _sendingVoice) {
          return KeyEventResult.ignored;
        }
        _desktopSpaceHeld = true;
        unawaited(_beginVoiceRecording());
        return KeyEventResult.handled;
      case DesktopVoiceMessageAction.stop:
        _desktopSpaceHeld = false;
        if (!_desktopPointerHeld) unawaited(_stopRec());
        return KeyEventResult.handled;
      case DesktopVoiceMessageAction.cancel:
        if (_recording || _voiceStart != null) {
          _cancelVoiceRecording();
        } else if (_desktopVoiceDraft != null) {
          _discardDesktopVoiceDraft();
        } else {
          _setPanel(_Panel.none);
          _desktopVoiceFocus.unfocus();
        }
        return KeyEventResult.handled;
      case DesktopVoiceMessageAction.none:
        return KeyEventResult.ignored;
    }
  }

  void _desktopVoicePointerDown(PointerDownEvent event) {
    if (_recording ||
        _desktopPointerHeld ||
        _voiceStop != null ||
        _desktopVoiceDraft != null ||
        _sendingVoice) {
      return;
    }
    _voicePointerId = event.pointer;
    _desktopPointerHeld = true;
    unawaited(_beginVoiceRecording());
  }

  void _desktopVoicePointerUp(PointerEvent event) {
    if (_voicePointerId != event.pointer) return;
    _voicePointerId = null;
    _desktopPointerHeld = false;
    if (!_desktopSpaceHeld) unawaited(_stopRec());
  }

  void _desktopVoicePointerCancel(PointerCancelEvent event) {
    if (_voicePointerId == event.pointer) _cancelVoiceRecording();
  }

  Future<void> _deleteTempFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  Future<String?> _waitForRecordingFile(String? path) async {
    if (path == null || path.isEmpty) return null;
    final file = File(path);
    var previousSize = -1;
    for (var attempt = 0; attempt < 20; attempt++) {
      try {
        if (await file.exists()) {
          final size = await file.length();
          if (size > 32 && size == previousSize) return path;
          previousSize = size;
        }
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    try {
      return await file.exists() && await file.length() > 32 ? path : null;
    } catch (_) {
      return null;
    }
  }

  void _toggle(_Panel panel) {
    _focus.unfocus();
    _setPanel(_panel == panel ? _Panel.none : panel);
  }

  void _pickFailed(String what) {
    _setPanel(_Panel.none);
    showToast(
      context,
      AppStrings.t(AppStringKeys.composerOpenAttachmentFailed, {
        'value1': what,
      }),
    );
  }

  void _closeDesktopVoicePanel() {
    _cancelVoiceRecording();
    _desktopVoiceFocus.unfocus();
    _setPanel(_Panel.none);
  }
}
