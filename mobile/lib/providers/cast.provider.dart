import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/entities/asset.entity.dart' as old_asset_entity;
import 'package:immich_mobile/models/cast/cast_manager_state.dart';
import 'package:immich_mobile/services/dlna.service.dart';
import 'package:immich_mobile/services/gcast.service.dart';

final castProvider = StateNotifierProvider<CastNotifier, CastManagerState>(
  (ref) => CastNotifier(ref.watch(gCastServiceProvider), ref.watch(dlnaServiceProvider)),
);

class CastNotifier extends StateNotifier<CastManagerState> {
  // more cast providers can be added here (ie Fcast)
  final GCastService _gCastService;
  final DlnaService _dlnaService;

  // track which service is currently active
  CastDestinationType? _activeType;

  List<(String, CastDestinationType, dynamic)> discovered = List.empty();

  CastNotifier(this._gCastService, this._dlnaService)
    : super(
        const CastManagerState(
          isCasting: false,
          currentTime: Duration.zero,
          duration: Duration.zero,
          receiverName: '',
          castState: CastState.idle,
        ),
      ) {
    _gCastService.onConnectionState = _onConnectionState;
    _gCastService.onCurrentTime = _onCurrentTime;
    _gCastService.onDuration = _onDuration;
    _gCastService.onReceiverName = _onReceiverName;
    _gCastService.onCastState = _onCastState;

    _dlnaService.onConnectionState = _onConnectionState;
    _dlnaService.onReceiverName = _onReceiverName;
  }

  void _onConnectionState(bool isCasting) {
    state = state.copyWith(isCasting: isCasting);
  }

  void _onCurrentTime(Duration currentTime) {
    state = state.copyWith(currentTime: currentTime);
  }

  void _onDuration(Duration duration) {
    state = state.copyWith(duration: duration);
  }

  void _onReceiverName(String receiverName) {
    state = state.copyWith(receiverName: receiverName);
  }

  void _onCastState(CastState castState) {
    state = state.copyWith(castState: castState);
  }

  void loadMedia(RemoteAsset asset, bool reload) {
    switch (_activeType) {
      case CastDestinationType.googleCast:
        _gCastService.loadMedia(asset, reload);
        break;
      case CastDestinationType.dlna:
        _dlnaService.loadMedia(asset, reload);
        break;
      case null:
        break;
    }
  }

  // TODO: remove this when we migrate to new timeline
  void loadMediaOld(old_asset_entity.Asset asset, bool reload) {
    final remoteAsset = RemoteAsset(
      id: asset.remoteId.toString(),
      name: asset.name,
      ownerId: asset.ownerId.toString(),
      checksum: asset.checksum,
      type: asset.type == old_asset_entity.AssetType.image
          ? AssetType.image
          : asset.type == old_asset_entity.AssetType.video
          ? AssetType.video
          : AssetType.other,
      createdAt: asset.fileCreatedAt,
      updatedAt: asset.updatedAt,
      isEdited: false,
    );

    loadMedia(remoteAsset, reload);
  }

  Future<void> connect(CastDestinationType type, dynamic device) async {
    _activeType = type;
    switch (type) {
      case CastDestinationType.googleCast:
        await _gCastService.connect(device);
        break;
      case CastDestinationType.dlna:
        await _dlnaService.connect(device);
        break;
    }
  }

  Future<List<(String, CastDestinationType, dynamic)>> getDevices() async {
    // discover gcast and dlna devices in parallel
    final results = await Future.wait([
      _gCastService.getDevices(),
      _dlnaService.getDevices(),
    ]);
    discovered = [...results[0], ...results[1]];
    return discovered;
  }

  void play() {
    switch (_activeType) {
      case CastDestinationType.googleCast:
        _gCastService.play();
        break;
      case CastDestinationType.dlna:
        _dlnaService.play();
        break;
      case null:
        break;
    }
  }

  void pause() {
    switch (_activeType) {
      case CastDestinationType.googleCast:
        _gCastService.pause();
        break;
      case CastDestinationType.dlna:
        _dlnaService.pause();
        break;
      case null:
        break;
    }
  }

  void seekTo(Duration position) {
    switch (_activeType) {
      case CastDestinationType.googleCast:
        _gCastService.seekTo(position);
        break;
      case CastDestinationType.dlna:
        _dlnaService.seekTo(position);
        break;
      case null:
        break;
    }
  }

  void stop() {
    switch (_activeType) {
      case CastDestinationType.googleCast:
        _gCastService.stop();
        break;
      case CastDestinationType.dlna:
        _dlnaService.stop();
        break;
      case null:
        break;
    }
  }

  Future<void> disconnect() async {
    switch (_activeType) {
      case CastDestinationType.googleCast:
        await _gCastService.disconnect();
        break;
      case CastDestinationType.dlna:
        await _dlnaService.disconnect();
        break;
      case null:
        break;
    }
    _activeType = null;
  }
}

