import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/l10n/app_localizations.dart';

/// Animated splash matching the brand mockup (assets/splash/splash_mockup.html):
/// the doko logo mark pops in, the "DokoDocs" wordmark fades up, and the
/// tagline words stagger in one by one. [onDone] fires once the sequence has
/// had time to play (or sooner if external init ever drives it).
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  // Brand colours (from the splash mockup / BRAND.md).
  static const _primary = Color(0xFF2E7D6B);
  static const _ink = Color(0xFF1E2422);
  static const _bg = Color(0xFFF7F9F8);

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..forward();
    // Hold briefly on the finished frame, then hand off.
    Timer(const Duration(milliseconds: 2300), widget.onDone);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// A fade + upward-slide, played over [start]..[end] of the controller.
  Widget _fadeUp({
    required double start,
    required double end,
    required Widget child,
    double offset = 12,
  }) {
    final anim = CurvedAnimation(
      parent: _controller,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (context, _) => Opacity(
        opacity: anim.value,
        child: Transform.translate(
          offset: Offset(0, (1 - anim.value) * offset),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tagline = l10n.onboardingTagline;
    final words = tagline.split(RegExp(r'\s+'));

    return Scaffold(
      backgroundColor: _bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Logo mark: scale-pop + fade.
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final t = CurvedAnimation(
                  parent: _controller,
                  curve: const Interval(0.0, 0.4, curve: Curves.easeOutBack),
                ).value;
                return Opacity(
                  opacity: t.clamp(0.0, 1.0),
                  child: Transform.scale(scale: 0.8 + 0.2 * t, child: child),
                );
              },
              child: SvgPicture.asset(
                'assets/logo/logo_dokodocs.svg',
                width: 140,
                height: 140,
                placeholderBuilder: (context) => Image.asset(
                  'assets/icon/logo_header.png',
                  width: 110,
                  height: 110,
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Wordmark: Doko (primary) + Docs (ink).
            _fadeUp(
              start: 0.45,
              end: 0.75,
              child: RichText(
                text: const TextSpan(
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.5,
                  ),
                  children: [
                    TextSpan(text: 'Doko', style: TextStyle(color: _primary)),
                    TextSpan(
                      text: 'Docs',
                      style: TextStyle(
                        color: _ink,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            // Tagline: each word staggers in.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < words.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: _fadeUp(
                      start: (0.6 + i * 0.06).clamp(0.0, 0.95),
                      end: (0.75 + i * 0.06).clamp(0.0, 1.0),
                      offset: 8,
                      child: Text(
                        words[i],
                        style: const TextStyle(
                          fontSize: 14,
                          color: _ink,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
