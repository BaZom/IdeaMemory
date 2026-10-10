import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'app.dart';
import 'config.dart';
import 'connection_check/connection_check_page.dart';
import 'connection_check/health_client.dart';

void main() {
  final Uri apiBaseUrl;
  try {
    apiBaseUrl = parseApiBaseUrl(apiBaseUrlDefine);
  } on FormatException catch (error) {
    runApp(ShellApp(home: ConfigurationErrorPage(message: error.message)));
    return;
  }

  final healthClient = HealthClient(
    baseUrl: apiBaseUrl,
    httpClient: http.Client(),
  );
  runApp(ShellApp(home: ConnectionCheckPage(healthClient: healthClient)));
}
