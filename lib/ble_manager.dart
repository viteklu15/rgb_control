import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Менеджер BLE: ищет по имени, выбирает лучшую по RSSI и подключается.
/// ИЗМЕНЕНО: Добавлена логика принудительного сканирования.
class BleManager {
  BleManager._();
  static final BleManager instance = BleManager._();

  final FlutterReactiveBle _ble = FlutterReactiveBle();

  static const String _storageKey = "last_known_mac_address";

  final ValueNotifier<DeviceConnectionState> _connState =
      ValueNotifier(DeviceConnectionState.disconnected);
  final ValueNotifier<int?> _lastRssi = ValueNotifier(null);
  final ValueNotifier<String?> _deviceName = ValueNotifier(null);
  final ValueNotifier<String?> _deviceId = ValueNotifier(null);

  final StreamController<DeviceConnectionState> _stateCtrl =
      StreamController<DeviceConnectionState>.broadcast();
  final StreamController<bool> _scanCtrl = StreamController<bool>.broadcast();
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
  bool _isConnecting = false;

  Future<void> ensureInitialized() async {
    if (_initialized) return;
    _initialized = true;
    await _ensurePermissions();
  }

  /// Главный метод подключения с новой логикой
  /// <--- ИЗМЕНЕНО: Добавлен параметр forceScan --->
  Future<void> connect({
    String targetName = "RGB_CONTROL_L",
    bool forceScan = false,
  }) async {
    if (_isConnecting || isConnected) return;
    _isConnecting = true;

    await disconnect();

    final lastMac = await _getLastMacAddress();

    // <--- ИЗМЕНЕНО: Проверяем флаг forceScan --->
    if (lastMac != null && !forceScan) {
      print('Attempting to connect to saved MAC: $lastMac');
      _update(DeviceConnectionState.connecting);
      _connSub = _ble.connectToDevice(
        id: lastMac,
        connectionTimeout: const Duration(seconds: 5),
      ).listen(
        (update) => _handleConnectionUpdate(update, onConnected: () {
          print('Successfully connected to saved MAC: $lastMac');
        }),
        onError: (e) {
          print('Failed to connect by MAC, starting scan...');
          _scanAndConnect(targetName);
        },
      );
    } else {
      if (forceScan) {
        print('Forcing scan by user request...');
      } else {
        print('No saved MAC address, starting scan...');
      }
      _scanAndConnect(targetName);
    }

    Future.delayed(const Duration(seconds: 1)).then((_) {
       if (_connState.value != DeviceConnectionState.connecting) {
         _isConnecting = false;
       }
    });
  }

  void _scanAndConnect(String targetName) async {
    _setScanning(true);
    DiscoveredDevice? bestDevice;
    final scanTimer = Timer(const Duration(seconds: 15), () {
        _scanSub?.cancel();
        _scanSub = null;
        if (bestDevice == null) {
          print('Scan finished. No devices found.');
          _setScanning(false);
          _update(DeviceConnectionState.disconnected);
           _isConnecting = false;
        } else {
          print('Scan finished. Best device found: ${bestDevice?.name} (${bestDevice?.id})');
          _setScanning(false);
          _update(DeviceConnectionState.connecting);
          _connSub = _ble.connectToDevice(id: bestDevice!.id).listen(
            (update) => _handleConnectionUpdate(update, onConnected: () {
              print('Successfully connected to scanned device: ${update.deviceId}');
              // <--- ВАЖНО: MAC-адрес меняется только после успешного подключения по имени --->
              _saveMacAddress(update.deviceId);
            }),
            onError: (_) => _isConnecting = false,
          );
        }
    });


    _scanSub = _ble.scanForDevices(withServices: []).listen((device) {
      if (device.name == targetName) {
        if (bestDevice == null || device.rssi > bestDevice!.rssi) {
          bestDevice = device;
        }
      }
    }, onError: (_) {
      _isConnecting = false;
      _setScanning(false);
    });
  }

  void _handleConnectionUpdate(ConnectionStateUpdate update, {VoidCallback? onConnected}) {
    _update(update.connectionState);
    if (update.connectionState == DeviceConnectionState.connected) {
      _deviceId.value = update.deviceId;
      _isConnecting = false;
      onConnected?.call();
    } else if(update.connectionState == DeviceConnectionState.disconnected){
       _isConnecting = false;
    }
  }

  Future<void> disconnect() async {
    await _scanSub?.cancel();
    await _connSub?.cancel();
    _scanSub = null;
    _connSub = null;
    _setScanning(false);
    if(connectionState != DeviceConnectionState.disconnected){
      _update(DeviceConnectionState.disconnected);
    }
    _isConnecting = false;
  }

  Future<String?> _getLastMacAddress() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_storageKey);
  }

  Future<void> _saveMacAddress(String mac) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, mac);
    print('Saved new MAC address: $mac');
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
      await Permission.bluetooth.request();
    }
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