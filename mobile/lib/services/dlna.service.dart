import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/models/cast/cast_manager_state.dart';
import 'package:immich_mobile/models/sessions/session_create_response.model.dart';
import 'package:immich_mobile/repositories/asset_api.repository.dart';
import 'package:immich_mobile/repositories/dlna.repository.dart';
import 'package:immich_mobile/repositories/sessions_api.repository.dart';
import 'package:immich_mobile/utils/image_url_builder.dart';
// ignore: import_rule_openapi, we are only using the AssetMediaSize enum
import 'package:openapi/api.dart';

final dlnaServiceProvider = Provider(
  (ref) => DlnaService(
    ref.watch(dlnaRepositoryProvider),
    ref.watch(sessionsAPIRepositoryProvider),
    ref.watch(assetApiRepositoryProvider),
  ),
);

class DlnaService {
  final DlnaRepository _dlnaRepository;
  final SessionsAPIRepository _sessionsApiService;
  final AssetApiRepository _assetApiRepository;

  SessionCreateResponse? sessionKey;
  String? currentAssetId;
  bool isConnected = false;
  String? _connectedDeviceName;

  void Function(bool)? onConnectionState;
  void Function(String)? onReceiverName;

  DlnaService(this._dlnaRepository, this._sessionsApiService, this._assetApiRepository) {
    _dlnaRepository.onConnectionState = _onConnectionStateCallback;
  }

  void _onConnectionStateCallback(bool connected) {
    isConnected = connected;
    onConnectionState?.call(connected);
    if (!connected) {
      onReceiverName?.call('');
      currentAssetId = null;
      _connectedDeviceName = null;
    }
  }

  CastDestinationType getType() {
    return CastDestinationType.dlna;
  }

  Future<bool> initialize() async {
    return true;
  }

  bool isSessionValid() {
    if (sessionKey == null || sessionKey?.expiresAt == null) {
      return false;
    }
    final tokenExpiration = DateTime.parse(sessionKey!.expiresAt!);
    final bufferedExpiration = tokenExpiration.subtract(const Duration(seconds: 10));
    return bufferedExpiration.isAfter(DateTime.now());
  }

  Future<void> connect(dynamic device) async {
    await _dlnaRepository.connect(device);
    _connectedDeviceName = _dlnaRepository.connectedDeviceName ?? 'DLNA';
    onReceiverName?.call(_connectedDeviceName!);
  }

  Future<void> disconnect() async {
    onReceiverName?.call('');
    currentAssetId = null;
    await _dlnaRepository.disconnect();
  }

  void loadMedia(RemoteAsset asset, bool reload) async {
    if (!isConnected) return;
    if (asset.id == currentAssetId && !reload) return;

    if (!isSessionValid()) {
      sessionKey = await _sessionsApiService.createSession(
        'Cast',
        'DLNA Cast',
        duration: const Duration(minutes: 15).inSeconds,
      );
    }

    final unauthenticatedUrl = asset.isVideo
        ? getPlaybackUrlForRemoteId(asset.id)
        : getThumbnailUrlForRemoteId(asset.id, type: AssetMediaSize.fullsize);

    final authenticatedURL = '$unauthenticatedUrl&sessionKey=${sessionKey?.token}';

    final mimeType = await _assetApiRepository.getAssetMIMEType(asset.id);
    if (mimeType == null) return;

    await _dlnaRepository.loadMedia(
      authenticatedURL,
      asset.name,
      isVideo: asset.isVideo,
    );

    currentAssetId = asset.id;
  }

  void play() async => _dlnaRepository.play();

  void pause() async => _dlnaRepository.pause();

  void seekTo(Duration position) async => _dlnaRepository.seek(position);

  void stop() async {
    await _dlnaRepository.stop();
    currentAssetId = null;
  }

  Future<List<(String, CastDestinationType, dynamic)>> getDevices() async {
    final devices = await _dlnaRepository.discoverDevices();
    return devices.map((d) => (d.$1, CastDestinationType.dlna, d.$2)).toList(growable: false);
  }
}
