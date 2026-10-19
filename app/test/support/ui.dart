import 'package:code2ticket/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ukuran layar (dp), skala font sistem, dan tema sistem untuk satu tes; dipulihkan otomatis sesudahnya.
Future<void> setViewport(
  WidgetTester tester, {
  double width = 360,
  double height = 800,
  double textScale = 1.0,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = Size(width * 3, height * 3);
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearAllTestValues();
  });
}

/// MaterialApp dengan tema aplikasi dan mode mengikuti sistem, seperti di main.dart.
Widget themedApp(Widget home) => MaterialApp(theme: AppTheme.light(), darkTheme: AppTheme.dark(), home: home);

/// Kombinasi yang wajib bebas overflow (DESIGN.md daftar periksa 9): lebar 360/428 dp, skala font 1,0 dan 1,3, terang dan gelap.
const layoutVariants = <({String name, double width, double scale, Brightness brightness})>[
  (name: '360 dp terang', width: 360, scale: 1.0, brightness: Brightness.light),
  (name: '428 dp gelap', width: 428, scale: 1.0, brightness: Brightness.dark),
  (name: '360 dp font 1,3x terang', width: 360, scale: 1.3, brightness: Brightness.light),
  (name: '360 dp font 1,3x gelap', width: 360, scale: 1.3, brightness: Brightness.dark),
  (name: '428 dp font 1,3x terang', width: 428, scale: 1.3, brightness: Brightness.light),
];
