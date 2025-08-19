import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../services/rgb_service.dart';
import '../ble_manager.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

class DemoRingScreen extends StatefulWidget {
  const DemoRingScreen({super.key});
  @override
  State<DemoRingScreen> createState() => _DemoRingScreenState();
}

class _DemoRingScreenState extends State<DemoRingScreen> {
  Color _currentColor = const Color(0xFFFF0000);
  bool _isOn = false;
  bool _policeMode = false;
  bool _autoColorMode = false;
  int _brightness = 10; // 0..10

  final _ble = BleManager.instance;

  // ---- автопереподключение ----
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  static const int _reconnectMaxDelaySec = 30;
  StreamSubscription? _statusSub;

  @override
  void initState() {
    super.initState();
    _ble.ensureInitialized();
    _ble.autoConnectToBest('RGB_CONTROL_L');

    _statusSub = _ble.statusStream.listen((_) {
      if (!mounted) return;
      final connected = _ble.isConnected;

      setState(() {
        if (!connected) {
          // При разрыве связи локально выключаем питание и режимы
          _isOn = false;
          _policeMode = false;
          _autoColorMode = false;
        }
      });

      if (connected) {
        _cancelReconnect();
      } else {
        _scheduleReconnect();
      }
    });
  }

  void _scheduleReconnect() {
    // Уже запланировано — выходим
    if (_reconnectTimer?.isActive ?? false) return;

    final exp = (_reconnectAttempt.clamp(0, 10) as int);
    final delaySec = min(_reconnectMaxDelaySec, 1 << exp); // 1,2,4,8,16,30...
    _reconnectAttempt++;

    _reconnectTimer = Timer(Duration(seconds: delaySec), () async {
      if (!_ble.isConnected) {
        await _ble.autoConnectToBest('RGB_CONTROL_L');
        // Дальнейшее планирование произойдёт из statusStream при неуспехе
      }
    });
  }

  void _cancelReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempt = 0;
  }

  @override
  void dispose() {
    _cancelReconnect();
    _statusSub?.cancel();
    super.dispose();
  }

  void _togglePower() async {
    setState(() {
      _isOn = !_isOn;
      if (!_isOn) {
        _policeMode = false;
        _autoColorMode = false;
      }
    });
    if (_ble.isConnected) {
      await RgbService.onPowerToggled(_isOn, current: _currentColor);
      // if (_isOn) {
      //   await RgbService.onBrightnessChanged(_brightness, withResponse: false);
      // }
    }
  }

  void _togglePoliceMode(bool value) {
    setState(() {
      _policeMode = value;
      if (value) _autoColorMode = false;
    });
    if (_ble.isConnected) RgbService.onPoliceMode(value);
  }

  void _toggleAutoColorMode(bool value) {
    setState(() {
      _autoColorMode = value;
      if (value) _policeMode = false;
    });
    if (_ble.isConnected) RgbService.onAutoColor(value);
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final h = MediaQuery.of(context).size.height;
    final ringSize = min(w, h) * 0.82;
    final ringStroke = ringSize * 0.14;
    final thumbSize = ringSize * 0.1;

    final connected = _ble.isConnected;
    final powerEnabled = connected; // кнопка питания активна только при подключении

    return Scaffold(
      body: Stack(
        children: [
          // Фон
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF061A2B),
                  Color(0xFF0A3350),
                  Color(0xFF0E5B76),
                ],
              ),
            ),
          ),
          Positioned(
            top: -h * 0.1,
            left: -w * 0.2,
            child: _blurSpot(w * 0.8, w * 0.8, const Color(0xFF23A6D5), 0.25),
          ),
          Positioned(
            bottom: -h * 0.15,
            right: -w * 0.3,
            child: _blurSpot(w * 0.9, w * 0.9, const Color(0xFF7FDBFF), 0.22),
          ),
          SafeArea(
            child: Column(
              children: [
                const _ConnectionIndicator(),
                const SizedBox(height: 8),
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Кольцевой цветовой пикер + кнопка питания
                        Transform.translate(
                          offset: Offset(0, -h * 0.04),
                          child: CircleColorPicker(
                            size: Size(ringSize, ringSize),
                            strokeWidth: ringStroke,
                            thumbSize: thumbSize,
                            initialColor: _currentColor,
                            enabled: _isOn && connected,
                            onChanged: (c) {
                              setState(() => _currentColor = c);
                              if (connected) {
                                RgbService.onColorChanged(c, isOn: _isOn);
                              }
                            },
                            center: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: (_isOn && powerEnabled)
                                    ? [
                                        BoxShadow(
                                          color: Colors.greenAccent.withOpacity(0.45),
                                          blurRadius: 32,
                                          spreadRadius: 2,
                                        ),
                                      ]
                                    : [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.25),
                                          blurRadius: 10,
                                          spreadRadius: 1,
                                        ),
                                      ],
                              ),
                              child: Opacity(
                                opacity: powerEnabled ? 1.0 : 0.55,
                                child: RawMaterialButton(
                                  onPressed: powerEnabled ? _togglePower : null,
                                  elevation: 0,
                                  fillColor: _isOn && powerEnabled
                                      ? const Color(0xFF11C56B)
                                      : Colors.white.withOpacity(powerEnabled ? 0.9 : 0.35),
                                  shape: const CircleBorder(),
                                  constraints: const BoxConstraints.tightFor(
                                    width: 122,
                                    height: 122,
                                  ),
                                  child: Icon(
                                    Icons.power_settings_new_rounded,
                                    size: 44,
                                    color: _isOn && powerEnabled
                                        ? Colors.white
                                        : (powerEnabled ? Colors.grey[700] : Colors.grey[500]),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Слайдер яркости
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Column(
                            children: [
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: BackdropFilter(
                                  filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: Colors.white.withOpacity(0.18), width: 1),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.wb_sunny_rounded,
                                              size: 18,
                                              color: (_isOn && connected) ? Colors.white : Colors.white38,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              'Яркость: $_brightness',
                                              style: TextStyle(
                                                color: (_isOn && connected) ? Colors.white : Colors.white38,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                        SliderTheme(
                                          data: SliderTheme.of(context).copyWith(
                                            activeTrackColor: Colors.lightBlueAccent,
                                            inactiveTrackColor: Colors.white24,
                                            thumbColor: Colors.lightBlueAccent,
                                            overlayColor: Colors.lightBlueAccent.withOpacity(0.2),
                                            trackHeight: 6,
                                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                                          ),
                                          child: Slider(
                                            min: 0,
                                            max: 10,
                                            divisions: 10,
                                            value: _brightness.toDouble(),
                                            onChanged: (_isOn && connected)
                                                ? (v) {
                                                    final b = v.round();
                                                    setState(() => _brightness = b);
                                                    RgbService.onBrightnessChanged(b, withResponse: false);
                                                  }
                                                : null,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 22),

                        // Плитка режимов
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: BackdropFilter(
                              filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.white.withOpacity(0.18), width: 1),
                                ),
                                child: Column(
                                  children: [
                                    _GlassSwitchTile(
                                      title: 'Мигалка',
                                      value: _policeMode,
                                      enabled: _isOn && connected,
                                      onChanged: (_isOn && connected) ? _togglePoliceMode : null,
                                    ),
                                    const Divider(height: 0, color: Colors.white24),
                                    _GlassSwitchTile(
                                      title: 'Автоцвет',
                                      value: _autoColorMode,
                                      enabled: _isOn && connected,
                                      onChanged: (_isOn && connected) ? _toggleAutoColorMode : null,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _blurSpot(double w, double h, Color c, double opacity) {
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [c.withOpacity(opacity), Colors.transparent],
        ),
      ),
    );
  }
}

class _ConnectionIndicator extends StatefulWidget {
  const _ConnectionIndicator();

  @override
  State<_ConnectionIndicator> createState() => _ConnectionIndicatorState();
}

class _ConnectionIndicatorState extends State<_ConnectionIndicator> {
  final _ble = BleManager.instance;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _sub = _ble.statusStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dot = switch (_ble.connectionState) {
      DeviceConnectionState.connected => Colors.green,
      DeviceConnectionState.connecting => Colors.orange,
      _ => Colors.red,
    };

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _ble.isConnected ? 'Подключено' : 'Поиск устройства',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (_ble.lastRssi != null)
            IconButton(
              onPressed: () => _ble.autoConnectToBest('RGB_CONTROL_L'),
              icon: const Icon(Icons.sync, color: Colors.white),
              tooltip: 'Переподключиться',
            ),
        ],
      ),
    );
  }
}

class _GlassSwitchTile extends StatelessWidget {
  final String title;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool enabled;

  const _GlassSwitchTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final tile = SwitchListTile.adaptive(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 6),
      title: Text(
        title,
        style: TextStyle(
          color: enabled ? Colors.white : Colors.white38,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
      value: value,
      onChanged: enabled ? onChanged : null,
      activeColor: const Color(0xFF7FDBFF),
      inactiveThumbColor: Colors.white70,
      inactiveTrackColor: Colors.white24,
    );

    return Opacity(opacity: enabled ? 1.0 : 0.5, child: tile);
  }
}

// ------------------- Кольцевой пикер -------------------
typedef ColorCodeBuilder = Widget Function(BuildContext context, Color color);

class CircleColorPicker extends StatefulWidget {
  const CircleColorPicker({
    super.key,
    required this.onChanged,
    this.size = const Size(280, 280),
    this.strokeWidth = 8,
    this.thumbSize = 28,
    this.initialColor = const Color(0xFFFF0000),
    this.textStyle = const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
    this.colorCodeBuilder,
    this.center,
    this.enabled = true,
  });

  final ValueChanged<Color> onChanged;
  final Size size;
  final double strokeWidth;
  final double thumbSize;
  final Color initialColor;
  final TextStyle textStyle;
  final ColorCodeBuilder? colorCodeBuilder;
  final Widget? center;
  final bool enabled;

  double get initialLightness => HSLColor.fromColor(initialColor).lightness;
  double get initialHue => HSLColor.fromColor(initialColor).hue;

  @override
  State<CircleColorPicker> createState() => _CircleColorPickerState();
}

class _CircleColorPickerState extends State<CircleColorPicker>
    with TickerProviderStateMixin {
  late final AnimationController _lightnessController;
  late final AnimationController _hueDegController;

  Color get _color =>
      HSLColor.fromAHSL(1, _hueDegController.value, 1, _lightnessController.value).toColor();

  @override
  void initState() {
    super.initState();
    _hueDegController = AnimationController(
      vsync: this,
      value: widget.initialHue,
      lowerBound: 0,
      upperBound: 360,
    )..addListener(_notify);
    _lightnessController = AnimationController(
      vsync: this,
      value: widget.initialLightness,
      lowerBound: 0,
      upperBound: 1,
    )..addListener(_notify);
  }

  void _notify() => widget.onChanged(_color);

  @override
  void dispose() {
    _hueDegController.dispose();
    _lightnessController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size.width,
      height: widget.size.height,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: widget.enabled ? 1.0 : 0.35,
            child: _HuePicker(
              size: widget.size,
              strokeWidth: widget.strokeWidth,
              thumbSize: widget.thumbSize,
              initialHueDeg: widget.initialHue,
              onRadiansChanged: (rad) => _hueDegController.value = (rad * 180 / pi) % 360,
              enabled: widget.enabled,
            ),
          ),
          if (widget.center != null) widget.center!,
        ],
      ),
    );
  }
}

class _HuePicker extends StatefulWidget {
  const _HuePicker({
    required this.onRadiansChanged,
    required this.size,
    required this.strokeWidth,
    required this.thumbSize,
    required this.initialHueDeg,
    this.enabled = true,
  });

  final ValueChanged<double> onRadiansChanged;
  final Size size;
  final double strokeWidth;
  final double thumbSize;
  final double initialHueDeg;
  final bool enabled;

  @override
  State<_HuePicker> createState() => _HuePickerState();
}

class _HuePickerState extends State<_HuePicker> with TickerProviderStateMixin {
  late final AnimationController _radiansController;
  late final AnimationController _scaleController;

  @override
  void initState() {
    super.initState();
    _radiansController = AnimationController(
      vsync: this,
      value: widget.initialHueDeg * pi / 180,
      lowerBound: 0,
      upperBound: 2 * pi,
    )..addListener(() => widget.onRadiansChanged(_radiansController.value));
    _scaleController = AnimationController(
      vsync: this,
      value: 1,
      lowerBound: .9,
      upperBound: 1,
      duration: const Duration(milliseconds: 50),
    );
  }

  @override
  void dispose() {
    _radiansController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  void _updateFromPos(Offset p) {
    final r = atan2(p.dy - widget.size.height / 2, p.dx - widget.size.width / 2);
    _radiansController.value = (r % (2 * pi));
  }

  @override
  Widget build(BuildContext context) {
    final cx = widget.size.width / 2;
    final cy = widget.size.height / 2;
    final s = min(widget.size.width, widget.size.height);
    final rOuter = s / 2 - widget.thumbSize / 2;
    final r = rOuter - widget.strokeWidth / 2;

    return IgnorePointer(
      ignoring: !widget.enabled,
      child: GestureDetector(
        onPanStart: (d) {
          _scaleController.reverse();
          _updateFromPos(d.localPosition);
        },
        onPanUpdate: (d) => _updateFromPos(d.localPosition),
        onPanEnd: (_) => _scaleController.forward(),
        child: SizedBox(
          width: widget.size.width,
          height: widget.size.height,
          child: Stack(
            children: [
              SizedBox.expand(
                child: Padding(
                  padding: EdgeInsets.all(widget.thumbSize / 2),
                  child: CustomPaint(painter: _RingPainter(widget.strokeWidth)),
                ),
              ),
              AnimatedBuilder(
                animation: _radiansController,
                builder: (_, __) {
                  final angle = _radiansController.value;
                  final left = cx + r * cos(angle) - widget.thumbSize / 2;
                  final top = cy + r * sin(angle) - widget.thumbSize / 2;
                  return Positioned(
                    left: left,
                    top: top,
                    child: ScaleTransition(
                      scale: _scaleController,
                      child: _Thumb(
                        size: widget.thumbSize,
                        color: HSLColor.fromAHSL(1, (angle * 180 / pi) % 360, 1, .5).toColor(),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter(this.strokeWidth);
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final R = min(size.width, size.height) / 2 - strokeWidth / 2;

    const grad = SweepGradient(
      colors: [
        Color(0xFFFF0000),
        Color(0xFFFFFF00),
        Color(0xFF00FF00),
        Color(0xFF00FFFF),
        Color(0xFF0000FF),
        Color(0xFFFF00FF),
        Color(0xFFFF0000),
      ],
    );

    final shader = grad.createShader(Rect.fromCircle(center: c, radius: R));

    canvas.drawCircle(
      c,
      R,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..shader = shader
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.strokeWidth != strokeWidth;
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 6, spreadRadius: 2)],
      ),
      alignment: Alignment.center,
      child: Container(
        width: size - 6,
        height: size - 6,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
    );
  }
}
