// Smoke test for SplashScreen. The previous version of this file imported
// a non-existent package (`package:manabu/main.dart` — this app's package
// is `nipino_manabu`) and tested a counter app that isn't part of this
// project at all, so it never actually compiled or ran.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:nipino_manabu/screens/splash_screen.dart';
import 'package:nipino_manabu/services/auth_provider.dart';

void main() {
  testWidgets('SplashScreen renders the logo before navigating away',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AuthProvider(),
        child: MaterialApp(
          home: const SplashScreen(),
          routes: {
            '/login': (_) => const Scaffold(body: Text('login')),
            '/home':  (_) => const Scaffold(body: Text('home')),
          },
        ),
      ),
    );

    await tester.pump();
    expect(find.text('日'), findsOneWidget);
    expect(find.byType(RichText), findsWidgets);

    // SplashScreen._navigate() fires a 2s Future.delayed regardless of
    // login state; the test binding asserts no pending timers remain when
    // the test ends, so pump past it (this AuthProvider never had
    // checkAuth() called, so isLoggedIn is false -> navigates to /login).
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.text('login'), findsOneWidget);
  });
}
