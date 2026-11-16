import 'package:flutter/material.dart';

/// Zapio "noir & champagne" design tokens.
class Lux {
  static const bg = Color(0xFF09090B);
  static const surface = Color(0xFF131316);
  static const surfaceHi = Color(0xFF1C1C21);
  static const line = Color(0x14FFFFFF); // 8% white hairline
  static const text = Color(0xFFF4F0E8);
  static const muted = Color(0xFF8F8A80);
  static const faint = Color(0xFF55524C);
  static const gold = Color(0xFFD9B676);
  static const goldLight = Color(0xFFF3DFAE);
  static const goldDeep = Color(0xFF9C7637);
  static const ruby = Color(0xFFE5484D);
  static const jade = Color(0xFF4CC38A);

  static const goldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [goldLight, gold, goldDeep],
  );

  static const keyGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF2A2A30), Color(0xFF16161A)],
  );

  static const font = 'BeVietnamPro';

  static ThemeData theme() {
    const scheme = ColorScheme.dark(
      primary: gold,
      onPrimary: Color(0xFF1A1407),
      secondary: goldLight,
      surface: surface,
      onSurface: text,
      error: ruby,
      outline: line,
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      fontFamily: font,
      scaffoldBackgroundColor: bg,
      splashFactory: InkSparkle.splashFactory,
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(bodyColor: text, displayColor: text),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: font, fontSize: 20, fontWeight: FontWeight.w600,
          color: text, letterSpacing: 0.2,
        ),
        iconTheme: IconThemeData(color: text),
      ),
      dividerColor: line,
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: surfaceHi,
        contentTextStyle: const TextStyle(fontFamily: font, color: text),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: line),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: const BorderSide(color: line),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceHi,
        hintStyle: const TextStyle(color: muted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: gold),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: gold,
          foregroundColor: const Color(0xFF1A1407),
          disabledBackgroundColor: surfaceHi,
          minimumSize: const Size(0, 54),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          textStyle: const TextStyle(fontFamily: font, fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          minimumSize: const Size(0, 54),
          side: const BorderSide(color: line),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          textStyle: const TextStyle(fontFamily: font, fontWeight: FontWeight.w500, fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: gold,
          textStyle: const TextStyle(fontFamily: font, fontWeight: FontWeight.w600),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: gold,
        linearTrackColor: surfaceHi,
      ),
      listTileTheme: const ListTileThemeData(iconColor: text),
      expansionTileTheme: const ExpansionTileThemeData(
        iconColor: gold,
        collapsedIconColor: muted,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceHi,
        side: const BorderSide(color: line),
        labelStyle: const TextStyle(fontFamily: font, color: text, fontSize: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      }),
    );
  }
}

/// Black canvas with two soft light pools (champagne top-left, cool bottom-right).
class LuxBackground extends StatelessWidget {
  const LuxBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: Lux.bg),
      child: Stack(children: [
        const Positioned(
          top: -160, left: -120,
          child: _Glow(color: Color(0x33D9B676), size: 420),
        ),
        const Positioned(
          bottom: -200, right: -160,
          child: _Glow(color: Color(0x1F3A6B7A), size: 480),
        ),
        Positioned.fill(child: child),
      ]),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
          ),
        ),
      );
}

/// Scaffold with the Lux background and a transparent app bar.
class LuxScaffold extends StatelessWidget {
  const LuxScaffold({super.key, this.title, this.actions, required this.body, this.bottom});
  final String? title;
  final List<Widget>? actions;
  final Widget body;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    return LuxBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: title == null && actions == null
            ? null
            : AppBar(title: title == null ? null : Text(title!), actions: actions),
        body: SafeArea(top: title == null && actions == null, child: body),
        bottomNavigationBar: bottom,
      ),
    );
  }
}

/// Glass card: subtle top-lit gradient, hairline border, large radius.
class LuxCard extends StatelessWidget {
  const LuxCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.padding = const EdgeInsets.all(18),
    this.radius = 26,
    this.highlight = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final br = BorderRadius.circular(radius);
    return Container(
      decoration: BoxDecoration(
        borderRadius: br,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: highlight
              ? const [Color(0xFF2A2417), Color(0xFF15130F)]
              : const [Color(0xFF1B1B20), Color(0xFF111114)],
        ),
        border: Border.all(color: highlight ? const Color(0x55D9B676) : Lux.line),
        boxShadow: const [
          BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 12)),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: br,
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Text painted with the champagne gradient.
class GoldText extends StatelessWidget {
  const GoldText(this.text, {super.key, this.style});
  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => ShaderMask(
        shaderCallback: (r) => Lux.goldGradient.createShader(r),
        blendMode: BlendMode.srcIn,
        child: Text(text, style: style),
      );
}

/// Circular badge holding an icon, gold-tinted ring.
class IconBadge extends StatelessWidget {
  const IconBadge(this.icon, {super.key, this.size = 52, this.gold = true});
  final IconData icon;
  final double size;
  final bool gold;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2B2619), Color(0xFF141310)],
          ),
          border: Border.all(color: gold ? const Color(0x66D9B676) : Lux.line),
        ),
        child: Icon(icon, size: size * 0.46, color: gold ? Lux.gold : Lux.text),
      );
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            fontSize: 12, letterSpacing: 1.6, color: Lux.muted, fontWeight: FontWeight.w600,
          ),
        ),
      );
}
