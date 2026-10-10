import 'package:flutter/material.dart';

/// User-visible product name; internal package and type names stay neutral.
const String appDisplayName = 'Idea Memory';

class ShellApp extends StatelessWidget {
  const ShellApp({super.key, required this.home});

  final Widget home;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF3F51B5);
    return MaterialApp(
      title: appDisplayName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: seed),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark),
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
