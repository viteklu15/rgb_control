import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

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

  Future<void> autoConnectToBest(String targetName,
      {Duration scanDuration = const Duration(seconds: 6)}) async {
    await disconnect();

    _setScanning(true);
    DiscoveredDevice? best;
    _scanSub?.cancel();
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
      _deviceId.value = null;
      _deviceName.value = null;
      _update(DeviceConnectionState.disconnected);
      return;
    }

    _lastRssi.value = best!.rssi;
    _deviceName.value = best!.name;
    _deviceId.value = best!.id;

    _connSub?.cancel();
    _update(DeviceConnectionState.connecting);

    _connSub = _ble
        .connectToDevice(id: best!.id, servicesWithCharacteristicsToDiscover: {})
        .listen((u) {
      _update(u.connectionState);
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
