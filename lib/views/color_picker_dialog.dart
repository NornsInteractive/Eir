import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_localization.dart';
import '../apple_glass.dart';

/// Shows a full-spectrum Liquid Glass Color Picker dialog supporting any arbitrary color.
Future<Color?> showLiquidGlassColorPicker(
  BuildContext context, {
  required Color initialColor,
  required String title,
}) {
  return showDialog<Color>(
    context: context,
    barrierColor: Colors.black54,
    builder: (ctx) => _ColorPickerDialog(
      initialColor: initialColor,
      title: title,
    ),
  );
}

class _ColorPickerDialog extends StatefulWidget {
  final Color initialColor;
  final String title;

  const _ColorPickerDialog({
    required this.initialColor,
    required this.title,
  });

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late HSVColor _hsv;
  late TextEditingController _hexController;
  bool _isUpdatingFromHex = false;

  static const List<Color> _curatedSwatches = [
    Color(0xFF007AFF), // Classic Blue
    Color(0xFF0A84FF), // Vivid Azure
    Color(0xFF30B0C7), // Cyan Sky
    Color(0xFF34C759), // Mint Green
    Color(0xFF30D158), // Electric Emerald
    Color(0xFFFF9500), // Sunset Orange
    Color(0xFFFF375F), // Radiant Coral
    Color(0xFFFF2D55), // Rose Berry
    Color(0xFF5856D6), // Deep Indigo
    Color(0xFFA259FF), // Cosmic Purple
    Color(0xFFE056FD), // Neon Lilac
    Color(0xFF686DE0), // Periwinkle
  ];

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initialColor);
    _hexController = TextEditingController(text: _colorToHex(_hsv.toColor()));
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  String _colorToHex(Color color) {
    return color.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase();
  }

  void _onHsvChanged(HSVColor newHsv) {
    setState(() {
      _hsv = newHsv;
      if (!_isUpdatingFromHex) {
        _hexController.text = _colorToHex(_hsv.toColor());
      }
    });
  }

  void _onHexSubmitted(String val) {
    var clean = val.replaceAll('#', '').trim().toUpperCase();
    if (clean.length == 6) {
      final intVal = int.tryParse('FF$clean', radix: 16);
      if (intVal != null) {
        _isUpdatingFromHex = true;
        final newColor = Color(intVal);
        _onHsvChanged(HSVColor.fromColor(newColor));
        _isUpdatingFromHex = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    final tc = ThemeColors.of(context);
    final curColor = _hsv.toColor();
    final size = MediaQuery.sizeOf(context);
    final isCompact = size.width < 420;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isCompact ? 340 : 380,
          maxHeight: size.height * 0.88,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: GlassContainer.card(
            surfaceStyle: GlassSurfaceStyle.glass,
            color: tc.cardBackground,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            shape: const LiquidRoundedSuperellipse(borderRadius: 22),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Title Bar
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.palette_rounded, size: 18, color: curColor),
                          const SizedBox(width: 8),
                          Text(
                            widget.title,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: tc.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      GlassIconButton(
                        size: 28,
                        icon: Icon(Icons.close_rounded, size: 16, color: tc.textSecondary),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Preview & Hex Header
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: tc.inputBackground,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        // Old Color chip
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: widget.initialColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white24, width: 1.5),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(Icons.arrow_forward_rounded, size: 14, color: tc.textTertiary),
                        const SizedBox(width: 6),
                        // New Color chip with glow
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: curColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: curColor.withValues(alpha: 0.4),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Hex Input
                        Expanded(
                          child: GlassTextField(
                            key: const ValueKey('color-picker-hex-input'),
                            controller: _hexController,
                            textStyle: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                            placeholder: '#RRGGBB',
                            onChanged: _onHexSubmitted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 2D Saturation / Value Area
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      height: 140,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanDown: (d) => _handleSatValGesture(d.localPosition, constraints),
                            onPanUpdate: (d) => _handleSatValGesture(d.localPosition, constraints),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                // Pure Hue Base
                                Container(color: HSVColor.fromAHSV(1.0, _hsv.hue, 1.0, 1.0).toColor()),
                                // Horizontal Saturation Gradient (White to Transparent)
                                Container(
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.centerLeft,
                                      end: Alignment.centerRight,
                                      colors: [Colors.white, Colors.transparent],
                                    ),
                                  ),
                                ),
                                // Vertical Value Gradient (Transparent to Black)
                                Container(
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [Colors.transparent, Colors.black],
                                    ),
                                  ),
                                ),
                                // Selector Indicator
                                Positioned(
                                  left: (_hsv.saturation * constraints.maxWidth - 9).clamp(0.0, constraints.maxWidth - 18),
                                  top: ((1.0 - _hsv.value) * constraints.maxHeight - 9).clamp(0.0, constraints.maxHeight - 18),
                                  child: Container(
                                    width: 18,
                                    height: 18,
                                    decoration: BoxDecoration(
                                      color: curColor,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white, width: 2.5),
                                      boxShadow: const [
                                        BoxShadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 1)),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Hue Rainbow Slider
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      height: 24,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanDown: (d) => _handleHueGesture(d.localPosition.dx, constraints.maxWidth),
                            onPanUpdate: (d) => _handleHueGesture(d.localPosition.dx, constraints.maxWidth),
                            child: Stack(
                              children: [
                                Container(
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Color(0xFFFF0000),
                                        Color(0xFFFFFF00),
                                        Color(0xFF00FF00),
                                        Color(0xFF00FFFF),
                                        Color(0xFF0000FF),
                                        Color(0xFFFF00FF),
                                        Color(0xFFFF0000),
                                      ],
                                    ),
                                  ),
                                ),
                                Positioned(
                                  left: ((_hsv.hue / 360.0) * constraints.maxWidth - 6).clamp(0.0, constraints.maxWidth - 12),
                                  top: 1,
                                  bottom: 1,
                                  child: Container(
                                    width: 12,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(6),
                                      boxShadow: const [
                                        BoxShadow(color: Colors.black38, blurRadius: 3),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Curated Swatches Row
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: _curatedSwatches.map((color) {
                      final isSelected = color.value == curColor.value;
                      return GestureDetector(
                        onTap: () => _onHsvChanged(HSVColor.fromColor(color)),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected ? Colors.white : Colors.transparent,
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: color.withValues(alpha: 0.3),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: isSelected
                              ? const Icon(Icons.check_rounded, size: 13, color: Colors.white)
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  // Actions
                  Row(
                    children: [
                      Expanded(
                        child: GlassButton.custom(
                          onTap: () => Navigator.of(context).pop(),
                          height: 36,
                          shape: const LiquidRoundedSuperellipse(borderRadius: 10),
                          child: Text(
                            i18n.cancel,
                            style: TextStyle(fontSize: 13, color: tc.textSecondary),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GlassButton.custom(
                          key: const ValueKey('color-picker-apply-btn'),
                          onTap: () => Navigator.of(context).pop(curColor),
                          height: 36,
                          style: GlassButtonStyle.prominent,
                          glowColor: tc.primary.withValues(alpha: 0.45),
                          shape: const LiquidRoundedSuperellipse(borderRadius: 10),
                          child: Text(
                            i18n.isZh ? '应用' : 'Apply',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _handleSatValGesture(Offset localPos, BoxConstraints constraints) {
    final sat = (localPos.dx / constraints.maxWidth).clamp(0.0, 1.0);
    final val = (1.0 - (localPos.dy / constraints.maxHeight)).clamp(0.0, 1.0);
    _onHsvChanged(_hsv.withSaturation(sat).withValue(val));
  }

  void _handleHueGesture(double localDx, double maxWidth) {
    final hue = ((localDx / maxWidth).clamp(0.0, 1.0) * 360.0).clamp(0.0, 360.0);
    _onHsvChanged(_hsv.withHue(hue));
  }
}
