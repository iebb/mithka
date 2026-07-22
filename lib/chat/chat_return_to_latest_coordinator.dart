enum ChatReturnToLatestSource { automatic, user }

class ChatReturnToLatestIntent {
  const ChatReturnToLatestIntent({required this.userInitiated});

  final bool userInitiated;
}

class ChatReturnToLatestFailure {
  const ChatReturnToLatestFailure({required this.userInitiated});

  final bool userInitiated;
}

/// Coordinates returning from an anchored history window to the latest edge.
///
/// TDLib requests cannot be physically cancelled once sent. A user drag
/// invalidates application of the old response, while a later button tap waits
/// for that request to finish before starting a fresh one.
class ChatReturnToLatestCoordinator {
  factory ChatReturnToLatestCoordinator({
    required Future<bool> Function() loadLatest,
    required void Function() invalidateLatestLoad,
    required bool Function() needsLatestLoad,
    required void Function() onChanged,
    required void Function() onReadyAvailable,
  }) => ChatReturnToLatestCoordinator._(
    loadLatest,
    invalidateLatestLoad,
    needsLatestLoad,
    onChanged,
    onReadyAvailable,
  );

  ChatReturnToLatestCoordinator._(
    this._loadLatest,
    this._invalidateLatestLoad,
    this._needsLatestLoad,
    this._onChanged,
    this._onReadyAvailable,
  );

  final Future<bool> Function() _loadLatest;
  final void Function() _invalidateLatestLoad;
  final bool Function() _needsLatestLoad;
  final void Function() _onChanged;
  final void Function() _onReadyAvailable;

  Future<bool>? _inFlight;
  bool _pending = false;
  bool _userInitiated = false;
  bool _automaticBlockedByDrag = false;
  bool _inFlightWasInvalidated = false;
  ChatReturnToLatestFailure? _failure;

  bool get pending => _pending;
  bool get loading => _inFlight != null;
  bool get showProgress => _pending && _userInitiated && loading;

  void request(ChatReturnToLatestSource source) {
    if (source == ChatReturnToLatestSource.automatic) {
      if (_automaticBlockedByDrag || _pending || _inFlight != null) return;
    }

    _pending = true;
    if (source == ChatReturnToLatestSource.user) {
      // A button tap upgrades an automatic request already in flight.
      _userInitiated = true;
    }
    _failure = null;
    _onChanged();
    _pump();
  }

  /// Cancels the intent only after a real user drag, not a pointer hold.
  void cancelForUserDrag() {
    if (_automaticBlockedByDrag && !_pending) return;
    _automaticBlockedByDrag = true;
    _cancelPendingIntent();
  }

  /// Cancels a competing navigation without changing drag gating.
  void cancel() {
    if (!_pending && _failure == null) return;
    _cancelPendingIntent();
  }

  void _cancelPendingIntent() {
    _pending = false;
    _userInitiated = false;
    _failure = null;
    if (_inFlight != null) {
      _inFlightWasInvalidated = true;
      _invalidateLatestLoad();
    }
    _onChanged();
  }

  void userDragEnded() {
    _automaticBlockedByDrag = false;
  }

  ChatReturnToLatestIntent? takeReady({required bool pointerDown}) {
    if (pointerDown || !_pending || loading || _needsLatestLoad()) return null;
    final intent = ChatReturnToLatestIntent(userInitiated: _userInitiated);
    _pending = false;
    _userInitiated = false;
    _onChanged();
    return intent;
  }

  ChatReturnToLatestFailure? takeFailure() {
    final failure = _failure;
    _failure = null;
    return failure;
  }

  void _pump() {
    if (!_pending) return;
    if (!_needsLatestLoad()) {
      _onReadyAvailable();
      return;
    }
    if (_inFlight != null) return;

    final request = _loadLatest();
    _inFlight = request;
    _inFlightWasInvalidated = false;
    _onChanged();
    request.then<void>(
      (_) => _complete(request),
      onError: (_) => _complete(request),
    );
  }

  void _complete(Future<bool> request) {
    if (!identical(_inFlight, request)) return;
    _inFlight = null;
    final shouldRetryAfterInvalidation = _inFlightWasInvalidated;
    _inFlightWasInvalidated = false;

    // A drag cancelled the old intent and no newer button tap replaced it.
    if (!_pending) {
      _onChanged();
      return;
    }

    if (!_needsLatestLoad()) {
      _onChanged();
      _onReadyAvailable();
      return;
    }

    if (shouldRetryAfterInvalidation) {
      // A new button tap arrived while an invalidated TDLib query was still
      // winding down. It now owns a fresh request.
      _onChanged();
      _pump();
      return;
    }

    final userInitiated = _userInitiated;
    _pending = false;
    _userInitiated = false;
    _failure = ChatReturnToLatestFailure(userInitiated: userInitiated);
    _onChanged();
  }
}
