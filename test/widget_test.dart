// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:responsi_2200016103_abdisetiawan/main.dart';

void main() {
  testWidgets('Halaman utama menampilkan form dan tab', (tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Tambah Mahasiswa'), findsOneWidget);
    expect(find.text('Daftar Mahasiswa'), findsOneWidget);
    expect(find.byIcon(Icons.qr_code_scanner), findsOneWidget);
  });
}
