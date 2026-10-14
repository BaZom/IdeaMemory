import 'package:flutter/material.dart';

/// User-visible product name; internal package and type names stay neutral.
const String appDisplayName = 'Oh, right!';

/// Warm accent; the rest of the palette is derived from it.
const Color appSeedColor = Color(0xFFE8704A);

ThemeData _theme(Brightness brightness) {
  final base = ThemeData(colorSchemeSeed: appSeedColor, brightness: brightness);
  return base.copyWith(
    cardTheme: const CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),
  );
}

class ShellApp extends StatelessWidget {
  const ShellApp({super.key, required this.home});

  final Widget home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: appDisplayName,
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: home,
    );
  }
}

/// Shown instead of the connection check when the build configuration is
/// invalid, so the problem is visible rather than a misleading network error.
class ConfigurationErrorPage extends StatelessWidget {
  const ConfigurationErrorPage({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configuration error')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Text(message, textAlign: TextAlign.center),
            ),
          ),
        ),
      ),
    );
  }
}
