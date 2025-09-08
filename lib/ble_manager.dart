import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Менеджер BLE: ищет по имени, выбирает лучшую по RSSI и подключается.
class BleManager {
  BleManager._();
  static final BleManager instance = BleManager._();

  final FlutterReactiveBle _ble = FlutterReactiveBle();

  final ValueNotifier<DeviceConnectionState> _connState =
      ValueNotifier(DeviceConnectionState.disconnected);
  final ValueNotifier<int?> _lastRssi = ValueNotifier(null);
  final ValueNotifier<String?> _deviceName = ValueNotifier(null);
  final ValueNotifier<String?> _deviceId = ValueNotifier(null);

  final StreamController<DeviceConnectionState> _stateCtrl =
      StreamController<DeviceConnectionState>.broadcast();
  final StreamController<bool> _scanCtrl =
      StreamController<bool>.broadcast();
  bool _scanning = false;

  Stream<DeviceConnectionState> get statusStream => _stateCtrl.stream;
  Stream<bool> get scanningStream => _scanCtrl.stream;
  DeviceConnectionState get connectionState => _connState.value;
  bool get isConnected => _connState.value == DeviceConnectionState.connected;
  bool get isScanning => _scanning;
  String get humanStatus => switch (_connState.value) {
        DeviceConnectionState.connected => 'Подключено',
        DeviceConnectionState.connecting => 'Подключение…',
        DeviceConnectionState.disconnected => 'Отключено',
        DeviceConnectionState.disconnecting => 'Отключение…',
      };
  int? get lastRssi => _lastRssi.value;
  String? get connectedDeviceId => _deviceId.value;
  String? get connectedDeviceName => _deviceName.value;

  StreamSubscription<DiscoveredDevice>? _scanSub;
  StreamSubscription<ConnectionStateUpdate>? _connSub;
  bool _initialized = false;

  Future<void> ensureInitialized() async {
    if (_initialized) return;
    _initialized = true;
    await _ensurePermissions();
  }

  Future<void> _ensurePermissions() async {
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final sdk = androidInfo.version.sdkInt;

      if (sdk >= 31) {
        final statuses = await [
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
        ].request();
        // Optional: если нужен advertise, добавьте Permission.bluetoothAdvertise
        if (statuses[Permission.bluetoothScan] != PermissionStatus.granted ||
            statuses[Permission.bluetoothConnect] != PermissionStatus.granted) {
          throw Exception('Нет разрешений на BLE (scan/connect)');
        }
      } else {
        final st = await Permission.locationWhenInUse.request();
        if (st != PermissionStatus.granted) {
          throw Exception('Нет разрешения на геолокацию для BLE-сканирования (Android < 12).');
        }
      }
    } else if (Platform.isIOS) {
      // На iOS системный диалог появляется при первом обращении к CoreBluetooth.
      // Явный запрос не обязателен, но можно проверить статус:
      await Permission.bluetooth.request();
    }
  }

  static const _prefsDeviceKey = 'last_device_mac';

  Future<bool> _connectToSaved(String id,
      {Duration timeout = const Duration(seconds: 4)}) async {
    _lastRssi.value = null;
    _deviceId.value = id;
    _deviceName.value = null;

    await _connSub?.cancel();
    _update(DeviceConnectionState.connecting);

    final completer = Completer<DeviceConnectionState>();
    _connSub = _ble
        .connectToDevice(id: id, servicesWithCharacteristicsToDiscover: {})
        .listen((u) {
      _update(u.connectionState);
      if (!completer.isCompleted &&
          (u.connectionState == DeviceConnectionState.connected ||
              u.connectionState == DeviceConnectionState.disconnected)) {
        completer.complete(u.connectionState);
      }
    }, onError: (_) {
      _update(DeviceConnectionState.disconnected);
      if (!completer.isCompleted) {
        completer.complete(DeviceConnectionState.disconnected);
      }
    });

    final state = await completer.future.timeout(timeout, onTimeout: () {
      _connSub?.cancel();
      _update(DeviceConnectionState.disconnected);
      return DeviceConnectionState.disconnected;
    });

    return state == DeviceConnectionState.connected;
  }

  Future<void> autoConnectToBest(String targetName,
      {Duration scanDuration = const Duration(seconds: 6),
      bool forceScan = false}) async {
    await disconnect();

    final prefs = await SharedPreferences.getInstance();

    if (!forceScan) {
      final savedId = prefs.getString(_prefsDeviceKey);
      if (savedId != null) {
        final connected = await _connectToSaved(savedId);
        if (connected) return;
      }
    }

    _setScanning(true);
    DiscoveredDevice? best;
    await _scanSub?.cancel();
    _scanSub = _ble
        .scanForDevices(
          withServices: const [],
          scanMode: ScanMode.balanced,
          requireLocationServicesEnabled: false,
        )
        .listen((d) {
      if (d.name == targetName) {
        if (best == null || d.rssi > best!.rssi) best = d;
      }
    }, onError: (_) {
      _update(DeviceConnectionState.disconnected);
    });

    await Future.delayed(scanDuration);
    await _scanSub?.cancel();
    _setScanning(false);

    if (best == null) {
      _lastRssi.value = null;
      _update(DeviceConnectionState.disconnected);
      return;
    }

    _lastRssi.value = best!.rssi;
    _deviceName.value = best!.name;
    final newId = best!.id;

    await _connSub?.cancel();
    _update(DeviceConnectionState.connecting);

    _connSub = _ble
        .connectToDevice(id: newId, servicesWithCharacteristicsToDiscover: {})
        .listen((u) {
      _update(u.connectionState);
      if (u.connectionState == DeviceConnectionState.connected) {
        _deviceId.value = newId;
        unawaited(prefs.setString(_prefsDeviceKey, newId));
      }
    }, onError: (_) {
      _update(DeviceConnectionState.disconnected);
    });
  }

  Future<void> disconnect() async {
    await _scanSub?.cancel();
    await _connSub?.cancel();
    _scanSub = null;
    _connSub = null;
    _setScanning(false);
    _update(DeviceConnectionState.disconnected);
  }

  /// Forget previously saved device identifier so that the next
  /// connection attempt will scan for a new device.
  Future<void> forgetDevice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsDeviceKey);
    _deviceId.value = null;
    _deviceName.value = null;
  }

  Future<void> writeBytes({
    required Uuid service,
    required Uuid characteristic,
    required List<int> value,
    bool withResponse = true,
  }) async {
    final id = connectedDeviceId;
    if (id == null || !isConnected) throw Exception('BLE не подключен');
    final ch = QualifiedCharacteristic(
      deviceId: id,
      serviceId: service,
      characteristicId: characteristic,
    );
    if (withResponse) {
      await _ble.writeCharacteristicWithResponse(ch, value: value);
    } else {
      await _ble.writeCharacteristicWithoutResponse(ch, value: value);
    }
  }

  /// Подписка на уведомления от характеристики.
  /// Возвращает поток байтов или пустой поток,
  /// если устройство не подключено.
  Stream<List<int>> subscribeToCharacteristic({
    required Uuid service,
    required Uuid characteristic,
  }) {
    final id = connectedDeviceId;
    if (id == null || !isConnected) {
      return const Stream<List<int>>.empty();
    }
    final ch = QualifiedCharacteristic(
      deviceId: id,
      serviceId: service,
      characteristicId: characteristic,
    );
    return _ble.subscribeToCharacteristic(ch);
  }

  void _update(DeviceConnectionState s) {
    if (_connState.value != s) {
      _connState.value = s;
      if (!_stateCtrl.isClosed) _stateCtrl.add(s);
    }
  }

  void _setScanning(bool s) {
    if (_scanning != s) {
      _scanning = s;
      if (!_scanCtrl.isClosed) _scanCtrl.add(s);
    }
  }

  void dispose() {
    _stateCtrl.close();
    _scanCtrl.close();
  }
}
