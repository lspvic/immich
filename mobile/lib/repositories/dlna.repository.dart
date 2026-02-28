import 'dart:async';

import 'package:dlna_dart/dlna.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final dlnaRepositoryProvider = Provider((_) => DlnaRepository());

class DlnaRepository {
  DLNAManager? _manager;
  DLNADevice? _currentDevice;

  void Function(bool)? onConnectionState;

  DlnaRepository();

  Future<List<(String, DLNADevice)>> discoverDevices({Duration timeout = const Duration(seconds: 5)}) async {
    _manager?.stop();
    _manager = DLNAManager();
    DeviceManager deviceManager;
    try {
      deviceManager = await _manager!.start();
    } catch (e) {
      _manager = null;
      return [];
    }

    Map<String, DLNADevice> latest = {};
    final sub = deviceManager.devices.stream.listen((devices) {
      latest = Map.from(devices);
    });

    await Future.delayed(timeout);

    await sub.cancel();
    _manager?.stop();
    _manager = null;

    return latest.entries
        .where((e) => _isMediaRenderer(e.value))
        .map((e) => (e.value.info.friendlyName, e.value))
        .toList(growable: false);
  }

  bool _isMediaRenderer(DLNADevice device) {
    return device.info.deviceType.contains('MediaRenderer') ||
        device.info.serviceList.any(
          (s) => (s['serviceId'] as String? ?? '').contains('AVTransport'),
        );
  }

  Future<void> connect(DLNADevice device) async {
    _currentDevice = device;
    onConnectionState?.call(true);
  }

  Future<void> loadMedia(String url, String title, {required bool isVideo}) async {
    if (_currentDevice == null) return;
    final type = isVideo ? PlayType.Video : PlayType.Image;
    await _currentDevice!.setUrl(url, title: title, type: type);
    await _currentDevice!.play();
  }

  Future<void> play() async {
    await _currentDevice?.play();
  }

  Future<void> pause() async {
    await _currentDevice?.pause();
  }

  Future<void> stop() async {
    await _currentDevice?.stop();
    _currentDevice = null;
    onConnectionState?.call(false);
  }

  Future<void> seek(Duration position) async {
    if (_currentDevice == null) return;
    final h = position.inHours.toString().padLeft(2, '0');
    final m = (position.inMinutes % 60).toString().padLeft(2, '0');
    final s = (position.inSeconds % 60).toString().padLeft(2, '0');
    await _currentDevice!.seek('$h:$m:$s');
  }

  Future<void> disconnect() async {
    await stop();
  }

  bool get isConnected => _currentDevice != null;

  String? get connectedDeviceName => _currentDevice?.info.friendlyName;
}
