part of 'chat_input_bar.dart';

extension _ChatInputBarAttachments on _ChatInputBarState {
  Future<void> _captureDesktopScreenshot() async {
    if (!_usesNativeDesktopComposer(context) || vm.editingMessage != null) {
      return;
    }
    String? path;
    try {
      final capture =
          widget.desktopScreenshotCapture ??
          DesktopScreenshotService.captureInteractiveRegion;
      path = await capture();
      if (!mounted || path == null || path.trim().isEmpty) return;
      _focus.unfocus();
      await _previewAndSendAttachments([
        OutgoingAttachment(
          path: path,
          kind: OutgoingAttachmentKind.photo,
          fileName: Uri.file(path).pathSegments.last,
        ),
      ]);
    } catch (error, stackTrace) {
      debugPrint('Failed to capture desktop screenshot: $error\n$stackTrace');
      if (mounted) {
        _pickFailed(AppStringKeys.composerScreenshot.l10n(context));
      }
    } finally {
      // Screen captures are user-selected temporary data. Keep them only for
      // the review/send flow and remove the local PNG after that flow ends.
      // Not awaited: the capture is finished once that flow returns, and
      // holding its future open for a best-effort delete makes every caller
      // wait on file I/O for nothing.
      if (path != null) unawaited(_deleteTempFile(path));
    }
  }

  Future<void> _pickPhotos() async {
    try {
      if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        await _pickDesktopPhotos();
        return;
      }
      // The quality choices live in the picker's own bottom bar, WeChat style,
      // so tapping 图片 goes straight to the grid.
      final selection = await AppAssetPicker.pickDetailed(
        context,
        type: AppAssetPickerType.imageAndVideo,
        maxAssets: 10,
        sendOptions: AppAssetSendOptions(),
      );
      if (!mounted) return;
      if (selection.failedCount > 0) {
        showToast(
          context,
          AppStrings.t(AppStringKeys.composerOpenAttachmentFailed, {
            'value1': AppStrings.t(AppStringKeys.composerImage),
          }),
        );
      }
      final attachments = selection.assets
          .map((asset) {
            final file = asset.file;
            final kind = galleryAttachmentKind(
              sendAsFile: false,
              isVideo: isPickedAssetVideo(file),
              isAnimation: isPickedAssetGif(file),
            );
            return OutgoingAttachment(
              path: file.path,
              kind: kind,
              fileName: asset.originalFile?.name ?? file.name,
              originalPath: asset.originalFile?.path,
              previewBytes: asset.thumbnailBytes,
              width: asset.width,
              height: asset.height,
            );
          })
          .toList(growable: false);
      if (attachments.isEmpty) return;
      await _previewAndSendAttachments(attachments);
    } catch (error, stackTrace) {
      debugPrint('Failed to send selected media: $error\n$stackTrace');
      _pickFailed(AppStrings.t(AppStringKeys.composerImage));
    }
  }

  Future<void> _pickDesktopPhotos() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const [
        'jpg',
        'jpeg',
        'png',
        'gif',
        'webp',
        'heic',
        'heif',
        'mp4',
        'mov',
        'mkv',
        'webm',
      ],
    );
    final files = result?.files
        .where((file) => file.path != null)
        .toList(growable: false);
    if (files == null || files.isEmpty || !mounted) return;
    if (files.length > 10) {
      showToast(
        context,
        AppStrings.t(AppStringKeys.composerMediaSelectionLimit, {'value1': 10}),
      );
      return;
    }
    final selected = files
        .map((file) {
          final path = file.path!;
          final pickedFile = XFile(path, name: file.name);
          return OutgoingAttachment(
            path: path,
            kind: galleryAttachmentKind(
              sendAsFile: false,
              isVideo: isPickedAssetVideo(pickedFile),
              isAnimation: isPickedAssetGif(pickedFile),
            ),
            fileName: file.name,
          );
        })
        .toList(growable: false);
    final attachments = await resolveAttachmentListDimensions(selected);
    if (!mounted) return;
    await _previewAndSendAttachments(attachments);
  }

  Future<void> _takePhoto() async {
    try {
      final capture = await captureComposerPhoto(
        context,
        saveToAlbum: context.read<ThemeController>().saveCapturedPhotosToAlbum,
      );
      if (capture == null || !mounted) return;
      if (capture.albumWriteFailed) {
        showToast(
          context,
          capture.albumResult == MediaLibrarySaveResult.permissionDenied
              ? AppStringKeys.chatSaveToPhotosPermissionDenied
              : AppStringKeys.chatSaveToPhotosFailed,
        );
      }
      final edited = await _editImage(capture.file.path);
      if (edited != null) {
        final attachment = await resolveAttachmentDimensions(
          OutgoingAttachment(
            path: edited.path,
            kind: OutgoingAttachmentKind.photo,
          ),
        );
        await widget.vm.sendAttachments([attachment], caption: edited.caption);
        widget.onMessageSent();
      }
    } catch (_) {
      _pickFailed(AppStrings.t(AppStringKeys.composerCamera));
    }
  }

  Future<void> _recordVideoNote() async {
    unawaited(_voiceDraft?.pause());
    try {
      final capture = await Navigator.of(context).push<VideoNoteCaptureResult>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => const VideoNoteRecorderView(),
        ),
      );
      if (!mounted || capture == null) return;
      final preview = await Navigator.of(context).push<VideoNotePreviewResult>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => VideoNotePreviewView(
            path: capture.path,
            allowWhenOnline: widget.vm.canSendWhenOnline,
            effects: widget.vm.availableMessageEffects,
          ),
        ),
      );
      if (!mounted) return;
      if (preview == null) {
        unawaited(_deleteTempFile(capture.path));
        return;
      }
      final sent = await widget.vm.sendVideoNote(
        preview.path,
        preview.duration,
        sendConfiguration: preview.sendConfiguration,
      );
      if (!mounted) return;
      if (sent) {
        widget.onMessageSent();
      } else {
        showToast(context, AppStringKeys.topicPostContentActionFailed);
      }
    } catch (_) {
      if (mounted) {
        showToast(context, AppStringKeys.topicPostContentActionFailed);
      }
    }
  }

  Future<ImageEditResult?> _editImage(
    String path, {
    String initialCaption = '',
  }) {
    return Navigator.of(context).push<ImageEditResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) =>
            ImageEditView(sourcePath: path, initialCaption: initialCaption),
      ),
    );
  }

  void _handleInsertedContent(KeyboardInsertedContent content) {
    unawaited(_sendInsertedImage(content));
  }

  Future<void> _queueKeyboardPastedImage(
    Uint8List data,
    String mimeType,
  ) async {
    // Same rules as a context-menu paste: an edit keeps its media, and the
    // field is read-only while a voice draft sends.
    if (vm.editingMessage != null || (_voiceDraft?.sending ?? false)) return;
    await _queueClipboardImageData(
      DesktopClipboardImageData(data: data, mimeType: mimeType),
    );
  }

  Future<void> _sendInsertedImage(KeyboardInsertedContent content) async {
    if (!content.mimeType.toLowerCase().startsWith('image/')) return;
    var data = content.data;
    var mimeType = content.mimeType;
    if (data == null || data.isEmpty) {
      final image = await _readInsertedImage(content.uri, content.mimeType);
      data = image?.data;
      mimeType = image?.mimeType ?? mimeType;
    }
    if (data == null || data.isEmpty) {
      if (mounted) {
        showToast(
          context,
          AppStrings.t(AppStringKeys.composerPastedImageReadFailed),
        );
      }
      return;
    }
    await _queueClipboardImageData(
      DesktopClipboardImageData(data: data, mimeType: mimeType),
    );
  }

  Future<_ClipboardImage?> _readInsertedImage(
    String uri,
    String mimeType,
  ) async {
    if (uri.isEmpty) return null;
    if (_usesNativeDesktopComposer(context)) {
      final parsed = Uri.tryParse(uri);
      if (parsed?.isScheme('file') == true) {
        try {
          final data = await File.fromUri(parsed!).readAsBytes();
          if (data.isNotEmpty) return (data: data, mimeType: mimeType);
        } on FileSystemException {
          return null;
        }
      }
    }
    try {
      final image = await _ChatInputBarState._clipboardChannel
          .invokeMapMethod<String, dynamic>('readImageUri', <String, dynamic>{
            'uri': uri,
            'mimeType': mimeType,
          });
      final data = image?['data'];
      if (data is! Uint8List || data.isEmpty) return null;
      return (
        data: data,
        mimeType: (image?['mimeType'] as String?) ?? mimeType,
      );
    } catch (_) {
      return null;
    }
  }

  Future<_ClipboardImage?> _readClipboardImage() async {
    try {
      final image = await _ChatInputBarState._clipboardChannel
          .invokeMapMethod<String, dynamic>('readImage');
      final data = image?['data'];
      if (data is! Uint8List || data.isEmpty) return null;
      final mimeType = (image?['mimeType'] as String?) ?? 'image/png';
      return (data: data, mimeType: mimeType);
    } catch (_) {
      return null;
    }
  }

  Future<bool> _queueDesktopClipboardImages() async {
    final remaining =
        _ChatInputBarState._maximumPendingClipboardAttachments -
        _pendingClipboardAttachments.length;
    if (remaining <= 0) {
      _showClipboardAttachmentLimit();
      return true;
    }
    final reader =
        widget.desktopClipboardAttachmentReader ??
        DesktopClipboardImageService.readAttachments;
    DesktopClipboardImageReadResult result;
    try {
      result = await reader(remaining);
    } catch (error, stackTrace) {
      debugPrint(
        'Failed to read desktop clipboard images: $error\n$stackTrace',
      );
      if (mounted) {
        showToast(
          context,
          AppStrings.t(AppStringKeys.composerPastedImageReadFailed),
        );
      }
      return false;
    }
    if (!mounted) return false;
    return _applyClipboardImageReadResult(result, remaining: remaining);
  }

  Future<bool> _queueClipboardImageData(DesktopClipboardImageData image) async {
    if (_voiceDraft != null) {
      // Only one attachment kind waits at a time; the picture is not added.
      if (mounted) {
        showToast(
          context,
          AppStrings.t(AppStringKeys.composerAttachmentWaiting),
        );
      }
      return true;
    }
    final remaining =
        _ChatInputBarState._maximumPendingClipboardAttachments -
        _pendingClipboardAttachments.length;
    if (remaining <= 0) {
      if (mounted) _showClipboardAttachmentLimit();
      return true;
    }
    try {
      final result = await DesktopClipboardImageService.storeImages([
        image,
      ], limit: remaining);
      if (!mounted) return false;
      return _applyClipboardImageReadResult(result, remaining: remaining);
    } catch (error, stackTrace) {
      debugPrint('Failed to store pasted image: $error\n$stackTrace');
      if (mounted) {
        showToast(
          context,
          AppStrings.t(AppStringKeys.composerPastedImageReadFailed),
        );
      }
      return false;
    }
  }

  bool _applyClipboardImageReadResult(
    DesktopClipboardImageReadResult result, {
    required int remaining,
  }) {
    if (result.availableImageCount == 0) return false;
    if (result.failedImageCount > 0) {
      showToast(
        context,
        AppStrings.t(AppStringKeys.composerPastedImageReadFailed),
      );
    }
    if (result.availableImageCount > remaining) {
      _showClipboardAttachmentLimit();
    }
    if (result.attachments.isNotEmpty) {
      _hideDesktopPopovers(rebuild: false);
      // Through _setPanel, so a recording in the voice panel is cancelled
      // rather than left running behind the pictures.
      _setPanel(_Panel.none);
      _updateState(() {
        _pendingClipboardAttachments.addAll(result.attachments);
        _replyKeyboardVisible = false;
        _quickReplyContextVisible = false;
      });
      widget.onPanelGeometryChanged?.call();
    }
    _restoreKeyboardFocus();
    return true;
  }

  void _showClipboardAttachmentLimit() {
    showToast(
      context,
      AppStrings.t(AppStringKeys.composerMediaSelectionLimit, {
        'value1': _ChatInputBarState._maximumPendingClipboardAttachments,
      }),
    );
  }

  Future<void> _previewAndSendAttachments(
    List<OutgoingAttachment> attachments,
  ) async {
    final MediaSendPreviewResult? preview;
    if (widget.mediaSendPreviewLauncher case final launcher?) {
      preview = await launcher(attachments);
    } else {
      final resolved = await resolveAttachmentListDimensions(attachments);
      if (!mounted) return;
      preview = await Navigator.of(context).push<MediaSendPreviewResult>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => MediaSendPreviewView(
            attachments: resolved,
            allowWhenOnline: widget.vm.canSendWhenOnline,
            effects: widget.vm.availableMessageEffects,
          ),
        ),
      );
    }
    if (!mounted || preview == null || preview.attachments.isEmpty) return;
    final finalAttachments = await resolveAttachmentListDimensions(
      preview.attachments,
    );
    await widget.vm.sendAttachments(
      finalAttachments,
      caption: preview.caption,
      sendConfiguration: preview.sendConfiguration,
    );
    widget.onMessageSent();
  }

  Future<void> _sendRichTextResult(RichTextComposerResult result) async {
    if (result.sendsAsFormattedText) {
      await _sendRichTextFormattedOnly(result, droppedRichBlocks: false);
      return;
    }
    var mode = await _richTextSendMode();
    if (!mounted) return;
    if (mode == null && result.hasRichBlocks) {
      // The document needs a capability this account does not have. Offer the
      // relay once; declining or a failed setup falls through to a plain
      // formatted message.
      var configured = false;
      try {
        configured = await _configureRichMessageRelay();
      } catch (error) {
        debugPrint('Rich text relay setup failed: $error');
      }
      if (!mounted) return;
      if (configured) mode = _RichTextSendMode.botRelay;
    }
    if (mode == null) {
      await _sendRichTextFormattedOnly(
        result,
        droppedRichBlocks: result.hasRichBlocks,
      );
      return;
    }
    try {
      var sentAny = false;
      if (mode == _RichTextSendMode.direct) {
        for (var index = 0; index < result.segments.length; index++) {
          final segment = result.segments[index];
          if (segment.isHtml) {
            final files = await Future.wait(
              segment.richFiles.map((file) async {
                final attachment = await resolveAttachmentDimensions(
                  file.attachment,
                );
                return RichMessageSendFile(id: file.id, attachment: attachment);
              }),
            );
            await widget.vm.sendRichMessageHtml(
              segment.html,
              files: files,
              blocks: segment.blocks,
            );
            sentAny = true;
          } else if (segment.attachments.isNotEmpty) {
            await widget.vm.sendAttachments(segment.attachments);
            sentAny = true;
          }
        }
      } else {
        sentAny = await _sendRichSegmentsViaRelay(result.segments);
      }
      if (!sentAny) return;
      widget.onMessageSent();
      _controller.clear();
      _focus.requestFocus();
    } catch (error, stackTrace) {
      debugPrint('Failed to send rich message: $error\n$stackTrace');
      if (mounted) {
        _setPanel(_Panel.none);
        final message = switch (error) {
          RichMessageRelayException(:final code)
              when code == 'bot_not_started' =>
            AppStringKeys.richTextRelayBotStartRequired.l10n(context),
          RichMessageRelayException(:final message)
              when message.trim().isNotEmpty =>
            message,
          TimeoutException() => AppStringKeys.composerRichTextSendFailed.l10n(
            context,
          ),
          TdError(:final message) when message.trim().isNotEmpty => message,
          _ =>
            error.toString().trim().isNotEmpty
                ? error.toString()
                : AppStringKeys.composerRichTextSendFailed.l10n(context),
        };
        showToast(context, message);
        await _reopenFailedRichTextComposer(result);
      }
    }
  }

  Future<void> _sendRichTextFormattedOnly(
    RichTextComposerResult result, {
    required bool droppedRichBlocks,
  }) async {
    if (result.text.trim().isEmpty || result.attachments.isNotEmpty) {
      showToast(
        context,
        AppStringKeys.richTextRelayPremiumOrBotRequired.l10n(context),
      );
      await _reopenFailedRichTextComposer(result);
      return;
    }
    final sent = await widget.vm.sendFormatted(result.text, result.entities);
    if (!mounted) return;
    if (!sent) {
      showToast(
        context,
        AppStringKeys.composerRichTextSendFailed.l10n(context),
      );
      await _reopenFailedRichTextComposer(result);
      return;
    }
    widget.onMessageSent();
    _controller.clear();
    _focus.requestFocus();
    if (droppedRichBlocks) {
      showToast(context, AppStringKeys.richTextSentFormattedOnly.l10n(context));
    }
  }

  Future<void> _reopenFailedRichTextComposer(
    RichTextComposerResult failedResult,
  ) async {
    if (!mounted) return;
    final result = await showRichTextComposerSheet(
      context,
      initialText: failedResult.text,
      initialEntities: failedResult.entities,
      initialAttachments: failedResult.attachments,
      title: AppStringKeys.composerRichTextMessageTitle,
      submitText: AppStringKeys.composerSend,
    );
    if (result == null || !mounted) return;
    if (result.text.trim().isEmpty &&
        result.attachments.isEmpty &&
        result.segments.isEmpty) {
      return;
    }
    final canAttemptSend = await vm.prepareMessageSend();
    if (!mounted || !canAttemptSend) return;
    if (vm.requiresPaidMessage) {
      final ok = await _confirmPaidMessageSend();
      if (!mounted || !ok) return;
    }
    await _sendRichTextResult(result);
  }

  Future<bool> _sendRichSegmentsViaRelay(
    List<RichMessageSendSegment> segments,
  ) async {
    var token = await RichMessageRelayConfig.readToken();
    if (token == null) {
      if (!mounted || !await _configureRichMessageRelay()) return false;
      token = await RichMessageRelayConfig.readToken();
    }
    if (token == null) return false;
    final currentUserId = await widget.vm.currentUserId();
    final relay = RichMessageBotRelay();
    var sentAny = false;
    _showRelayProgress();
    // A relayed copy is a forward the view model never builds, so the "All"
    // view's topic is resolved here, once for the whole burst, and handed to
    // every copy: a rich document must not open one topic per segment.
    RichMessageSendSegment? titledSegment;
    for (final segment in segments) {
      if (segment.isHtml) {
        titledSegment = segment;
        break;
      }
    }
    final topicRef = titledSegment == null
        ? await widget.vm.botTopicRefForSend()
        : await widget.vm.botTopicRefForSend(
            html: titledSegment.html,
            blocks: titledSegment.blocks,
          );
    try {
      for (final segment in segments) {
        if (segment.isHtml) {
          final files = await Future.wait(
            segment.richFiles.map((file) async {
              final relayAttachment = await _resolveRelayAttachment(
                file.attachment,
              );
              final attachment = await resolveAttachmentDimensions(
                relayAttachment,
              );
              return RichMessageSendFile(id: file.id, attachment: attachment);
            }),
          );
          await relay.sendAndCopy(
            token: token,
            html: segment.html,
            currentUserId: currentUserId,
            targetChatId: widget.vm.chatId,
            tdClient: TdClient.shared,
            files: files,
            blocks: segment.blocks,
            topicRef: topicRef,
            onProgress: _updateRelayProgress,
          );
          sentAny = true;
          widget.vm.announceBotTopicRef(topicRef);
        } else {
          for (final attachment in segment.attachments) {
            await relay.sendAttachmentAndCopy(
              token: token,
              attachment: attachment,
              currentUserId: currentUserId,
              targetChatId: widget.vm.chatId,
              tdClient: TdClient.shared,
              topicRef: topicRef,
              onProgress: _updateRelayProgress,
            );
            sentAny = true;
            widget.vm.announceBotTopicRef(topicRef);
          }
        }
      }
    } finally {
      relay.close();
      _hideRelayProgress();
    }
    return sentAny;
  }

  Future<OutgoingAttachment> _resolveRelayAttachment(
    OutgoingAttachment attachment,
  ) async {
    final path = attachment.path.trim();
    if (path.isNotEmpty && await File(path).exists()) return attachment;
    final fileId = attachment.fileId;
    if (fileId == null || fileId <= 0) {
      throw StateError('Unable to read rich message media');
    }
    final downloaded = await TdFileCenter.shared.uploadPath(fileId);
    if (downloaded == null ||
        downloaded.isEmpty ||
        !await File(downloaded).exists()) {
      throw StateError('Unable to download rich message media');
    }
    return attachment.copyWith(path: downloaded);
  }

  void _showRelayProgress() {
    if (_relayProgressEntry != null || !mounted) return;
    final overlay = Overlay.of(context, rootOverlay: true);
    _relayProgress = const RichMessageRelayProgress(
      stage: RichMessageRelayStage.compose,
      step: 1,
      totalSteps: 3,
    );
    final entry = OverlayEntry(
      builder: (_) => _RelaySendingOverlay(progress: _relayProgress!),
    );
    _relayProgressEntry = entry;
    overlay.insert(entry);
  }

  void _updateRelayProgress(RichMessageRelayProgress progress) {
    _relayProgress = progress;
    _relayProgressEntry?.markNeedsBuild();
  }

  void _hideRelayProgress() {
    final entry = _relayProgressEntry;
    _relayProgressEntry = null;
    _relayProgress = null;
    if (entry?.mounted ?? false) entry!.remove();
  }

  Future<_RichTextSendMode?> _richTextSendMode() async {
    try {
      if (await TdClient.shared.activeAccountUsesBotApi()) {
        return _RichTextSendMode.direct;
      }
      if (await widget.vm.currentUserIsPremium()) {
        return _RichTextSendMode.direct;
      }
      if (await RichMessageRelayConfig.isConfigured()) {
        return _RichTextSendMode.botRelay;
      }
    } catch (_) {
      // Capability probing is advisory here: a failure leaves the caller on the
      // plain formatted-message path rather than replacing the message with a
      // probe error.
    }
    return null;
  }

  Future<bool> _configureRichMessageRelay() async {
    final configure = await confirmDialog(
      context,
      title: AppStringKeys.richTextRelayBotSetupTitle.l10n(context),
      message: AppStringKeys.richTextRelayBotSetupDescription.l10n(context),
      confirmText: AppStringKeys.richTextRelayBotConfigure.l10n(context),
    );
    if (!mounted || !configure) return false;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const RichMessageRelayView()),
    );
    return mounted && await RichMessageRelayConfig.isConfigured();
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: true);
      final attachments = result?.files
          .map((file) => file.path)
          .whereType<String>()
          .take(10)
          .map(
            (path) => OutgoingAttachment(
              path: path,
              kind: OutgoingAttachmentKind.document,
            ),
          )
          .toList();
      if (attachments == null || attachments.isEmpty) return;
      await widget.vm.sendAttachments(attachments);
      widget.onMessageSent();
    } catch (_) {
      _pickFailed(AppStrings.t(AppStringKeys.topicPostContentFile));
    }
  }

  Future<void> _openDesktopComposerPicker(
    DesktopUtilityWindowKind kind,
    String title,
  ) async {
    final utilityWindows = DesktopUtilityWindowService.instance;
    final open = widget.desktopUtilityWindowLauncher ?? utilityWindows.open;
    final opened = await open(
      DesktopUtilityWindowArguments(
        kind: kind,
        accountSlot: TdClient.shared.activeSlot,
        accountUserId: vm.meId,
        chatId: vm.chatId,
        title: title,
        localeTag: Localizations.localeOf(context).toLanguageTag(),
        dark: Theme.of(context).brightness == Brightness.dark,
      ),
    );
    if (!opened && mounted) _pickFailed(title);
  }

  Future<void> _sendLocation() async {
    if (_usesNativeDesktopComposer(context)) {
      await _openDesktopComposerPicker(
        DesktopUtilityWindowKind.locationPicker,
        AppStringKeys.composerLocation.l10n(context),
      );
      return;
    }
    final start = await resolveLocationPickerStart();
    if (!mounted) return;
    final picked = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(builder: (_) => LocationPickerView(initial: start)),
    );
    if (picked != null) {
      widget.vm.sendLocation(picked.latitude, picked.longitude);
      widget.onMessageSent();
    }
  }

  Future<void> _sendContact() async {
    if (_usesNativeDesktopComposer(context)) {
      await _openDesktopComposerPicker(
        DesktopUtilityWindowKind.contactPicker,
        AppStringKeys.composerContact.l10n(context),
      );
      return;
    }
    final contact = await Navigator.of(context).push<MessageContactCard>(
      MaterialPageRoute(builder: (_) => const ContactSharePickerView()),
    );
    if (!mounted || contact == null) return;
    final sent = await widget.vm.sendContact(contact);
    if (!mounted) return;
    if (sent) {
      widget.onMessageSent();
    } else {
      showToast(context, AppStringKeys.topicPostContentActionFailed);
    }
  }

  Future<void> _createPoll() async {
    if (_usesNativeDesktopComposer(context)) {
      await _openDesktopComposerPicker(
        DesktopUtilityWindowKind.pollComposer,
        AppStringKeys.pollComposerCreatePollTitle.l10n(context),
      );
      return;
    }
    final maxOptions = await widget.vm.pollAnswerCountMax();
    if (!mounted) return;
    final result = await Navigator.of(context).push<PollComposerResult>(
      MaterialPageRoute(
        builder: (_) => PollComposerView(maxOptions: maxOptions),
      ),
    );
    if (!mounted || result == null) return;
    final sent = await widget.vm.sendPoll(result);
    if (!mounted) return;
    if (sent) {
      widget.onMessageSent();
    } else {
      showToast(context, AppStringKeys.topicPostContentActionFailed);
    }
  }

  Future<void> _pickLocalAudio() async {
    try {
      final preferred = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: const [
          'mp3',
          'm4a',
          'aac',
          'flac',
          'wav',
          'ogg',
          'opus',
          'amr',
        ],
      );
      final result =
          preferred ?? await FilePicker.platform.pickFiles(allowMultiple: true);
      if (result == null) return;
      final attachments = result.files
          .map((file) => file.path)
          .whereType<String>()
          .take(10)
          .map(
            (path) => OutgoingAttachment(
              path: path,
              kind: OutgoingAttachmentKind.audio,
            ),
          )
          .toList();
      if (attachments.isEmpty) return;
      await widget.vm.sendAttachments(attachments);
      widget.onMessageSent();
    } catch (_) {
      _pickFailed(AppStrings.t(AppStringKeys.composerAudio));
    }
  }

  Future<void> _pickAudio() async {
    if (_usesNativeDesktopComposer(context)) {
      await _openDesktopComposerPicker(
        DesktopUtilityWindowKind.audioPicker,
        AppStrings.t(AppStringKeys.composerAudio),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AudioSearchView(
          onSend: (sourceChatId, message) async {
            await widget.vm.sendAudioFromMessage(sourceChatId, message);
            widget.onMessageSent();
          },
          onPickLocal: _pickLocalAudio,
        ),
      ),
    );
  }

  Future<void> _createChecklist() async {
    if (_usesNativeDesktopComposer(context)) {
      await _openDesktopComposerPicker(
        DesktopUtilityWindowKind.checklistComposer,
        AppStringKeys.checklistComposerNewChecklistTitle.l10n(context),
      );
      return;
    }
    final result = await Navigator.of(context).push<ChecklistComposerResult>(
      MaterialPageRoute(builder: (_) => const ChecklistComposerView()),
    );
    if (result == null) return;
    if (result.title.isEmpty || result.tasks.isEmpty) return;
    widget.vm.sendChecklist(result);
    widget.onMessageSent();
  }

  Future<void> _createSuggestedPost() async {
    final loader = ChannelDirectMessageTopicController(
      chatId: vm.chatId,
      topicId: 0,
    );
    try {
      final limits = await loader.loadLimits();
      if (!mounted) return;
      final draft = await showAppModalSheet<SuggestedPostDraft>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => SuggestedPostComposerSheet(limits: limits),
      );
      if (draft == null || !mounted) return;
      await vm.sendSuggestedPost(
        text: draft.text,
        attachment: draft.attachment,
        price: draft.price,
        sendDate: draft.sendDate,
      );
      widget.onMessageSent();
    } catch (error) {
      if (mounted) showToast(context, error.toString());
    } finally {
      loader.dispose();
    }
  }
}
