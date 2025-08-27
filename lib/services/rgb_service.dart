import 'dart:convert';
import 'package:flutter/material.dart';
import '../ble_manager.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

/// Сервис команд RGB. Подмените UUID под ваш прошивочный протокол.
class RgbService {
  // ЗАМЕНИТЕ на ваши UUID
  static final Uuid _svc = Uuid.parse("12345678-1234-1234-1234-123456789abc");
  static final Uuid _ch  = Uuid.parse("87654321-4321-4321-4321-abcdefabcdef");

  static Future<void> _sendString(String s, {bool withResponse = true}) async {
    final ble = BleManager.instance;
    if (!ble.isConnected) return;
    await ble.writeBytes(
      service: _svc,
      characteristic: _ch,
      value: utf8.encode(s),
      withResponse: withResponse,
    );
  }

  static Future<void> onPowerToggled(bool isOn, {required Color current}) async {
    await _sendString("PWR:${isOn ? 1 : 0}\n");
    if (isOn) {
      await _sendString("RGB:${current.red},${current.green},${current.blue}\n");
    }
  }

  static Future<void> onColorChanged(Color c, {required bool isOn}) async {
    if (!isOn) return;
    await _sendString("RGB:${c.red},${c.green},${c.blue}\n", withResponse: false);
  }

  // НОВОЕ: управление яркостью (0..255)
  static Future<void> onBrightnessChanged(int brightness, {bool withResponse = false}) async {
    // предполагаемый протокол: "BRI:<0..255>\n"
    await _sendString("BRI:$brightness\n", withResponse: withResponse);
  }

  static Future<void> onPoliceMode(bool enabled) async {
    await _sendString("POL:${enabled ? 1 : 0}\n");
  }

  static Future<void> onAutoColor(bool enabled) async {
    await _sendString("AUTO:${enabled ? 1 : 0}\n");
  }

  static Future<void> onCommandNumber(int number) async {
    await _sendString("LED:$number\n");
  }

  /// Поток уведомлений от устройства.
  static Stream<List<int>> statusStream() {
    return BleManager.instance.subscribeToCharacteristic(
      service: _svc,
      characteristic: _ch,
    );
  }
}
