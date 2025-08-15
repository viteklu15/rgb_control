import 'dart:math';
import 'package:flutter/material.dart';

void main() => runApp(
  const MaterialApp(debugShowCheckedModeBanner: false, home: DemoRingScreen()),
);

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

  void _togglePower() => setState(() => _isOn = !_isOn);

  void _togglePoliceMode(bool value) {
    setState(() {
      _policeMode = value;
      if (value) _autoColorMode = false; // выключить автоцвет
    });
  }

  void _toggleAutoColorMode(bool value) {
    setState(() {
      _autoColorMode = value;
      if (value) _policeMode = false; // выключить полицию
    });
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final h = MediaQuery.of(context).size.height;
    final ringSize = min(w, h) * 0.9;
    final ringStroke = ringSize * 0.16;
    final thumbSize = ringSize * 0.1;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleColorPicker(
                size: Size(ringSize, ringSize),
                strokeWidth: ringStroke,
                thumbSize: thumbSize,
                initialColor: _currentColor,
                onChanged: (c) {
                  setState(() => _currentColor = c);
                  // TODO: отправить цвет на устройство
                },
                center: RawMaterialButton(
                  onPressed: _togglePower,
                  elevation: 9,
                  fillColor: _isOn
                      ? Colors.green.withOpacity(0.85)
                      : Colors.white.withOpacity(0.9),
                  shape: const CircleBorder(),
                  constraints: const BoxConstraints.tightFor(
                    width: 120,
                    height: 120,
                  ),
                  child: Icon(
                    Icons.power_settings_new,
                    size: 42,
                    color: _isOn ? Colors.white : Colors.grey,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // переключатель "Полиция"
              SwitchListTile(
                title: const Text("Полиция"),
                value: _policeMode,
                onChanged: _togglePoliceMode,
              ),

              // переключатель "Автоцвет"
              SwitchListTile(
                title: const Text("Автоцвет"),
                value: _autoColorMode,
                onChanged: _toggleAutoColorMode,
              ),
            ],
          ),
        ),
      ),
    );
  }
}


typedef ColorCodeBuilder = Widget Function(BuildContext context, Color color);

class CircleColorPicker extends StatefulWidget {
  const CircleColorPicker({
    Key? key,
    required this.onChanged,
    this.size = const Size(280, 280),
    this.strokeWidth = 8,
    this.thumbSize = 28,
    this.initialColor = const Color(0xFFFF0000),
    this.textStyle = const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
    this.colorCodeBuilder,
    this.center,
  }) : super(key: key);

  final ValueChanged<Color> onChanged;
  final Size size;
  final double strokeWidth;
  final double thumbSize;
  final Color initialColor;
  final TextStyle textStyle;
  final ColorCodeBuilder? colorCodeBuilder;
  final Widget? center;

  double get initialLightness => HSLColor.fromColor(initialColor).lightness;
  double get initialHue => HSLColor.fromColor(initialColor).hue;

  @override
  State<CircleColorPicker> createState() => _CircleColorPickerState();
}

class _CircleColorPickerState extends State<CircleColorPicker>
    with TickerProviderStateMixin {
  late final AnimationController _lightnessController; // [0..1]
  late final AnimationController _hueDegController; // [0..360]

  Color get _color =>
      HSLColor.fromAHSL(
        1,
        _hueDegController.value,
        1,
        _lightnessController.value,
      ).toColor();

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
          _HuePicker(
            size: widget.size,
            strokeWidth: widget.strokeWidth,
            thumbSize: widget.thumbSize,
            initialHueDeg: widget.initialHue,
            onRadiansChanged:
                (rad) => _hueDegController.value = (rad * 180 / pi) % 360,
          ),
          if (widget.center != null) widget.center!,
        ],
      ),
    );
  }
}

class _HuePicker extends StatefulWidget {
  const _HuePicker({
    Key? key,
    required this.onRadiansChanged,
    required this.size,
    required this.strokeWidth,
    required this.thumbSize,
    required this.initialHueDeg,
  }) : super(key: key);

  final ValueChanged<double> onRadiansChanged; // радианы
  final Size size;
  final double strokeWidth;
  final double thumbSize;
  final double initialHueDeg;

  @override
  State<_HuePicker> createState() => _HuePickerState();
}

class _HuePickerState extends State<_HuePicker> with TickerProviderStateMixin {
  late final AnimationController _radiansController; // [0..2π]
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
    final r = atan2(
      p.dy - widget.size.height / 2,
      p.dx - widget.size.width / 2,
    );
    _radiansController.value = (r % (2 * pi));
  }

  @override
  Widget build(BuildContext context) {
    final cx = widget.size.width / 2;
    final cy = widget.size.height / 2;
    final s = min(widget.size.width, widget.size.height);
    final rOuter = s / 2 - widget.thumbSize / 2; // внешний край кольца
    final r = rOuter - widget.strokeWidth / 2; // центр цветной полосы

    return GestureDetector(
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
            // резерв под бегунок, чтобы не обрезался
            SizedBox.expand(
              child: Padding(
                padding: EdgeInsets.all(widget.thumbSize / 2),
                child: CustomPaint(painter: _RingPainter(widget.strokeWidth)),
              ),
            ),
            // бегунок: позиция считается от центра, минус половина его размера
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
                      color:
                          HSLColor.fromAHSL(
                            1,
                            (angle * 180 / pi) % 360,
                            1,
                            .5,
                          ).toColor(),
                    ),
                  ),
                );
              },
            ),
          ],
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
    final R =
        min(size.width, size.height) / 2 - strokeWidth / 2; // центр полосы

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
        ..shader = shader,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.strokeWidth != strokeWidth;
}

class _Thumb extends StatelessWidget {
  const _Thumb({Key? key, required this.size, required this.color})
    : super(key: key);
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
        boxShadow: [
          BoxShadow(color: Color(0x29000000), blurRadius: 4, spreadRadius: 2),
        ],
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
