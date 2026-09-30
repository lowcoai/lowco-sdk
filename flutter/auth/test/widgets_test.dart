import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lowcoai_auth/lowcoai_auth.dart';

import 'helpers.dart';

Widget _app(LowcoAuth auth, Widget child) => Directionality(
      textDirection: TextDirection.ltr,
      child: LowcoAuthProvider(auth: auth, child: child),
    );

const _guarded = WithAuthenticationRequired(
  placeholder: Text('placeholder'),
  child: Text('secret'),
);

/// Unmounts the tree and disposes [auth] so no refresh timer outlives the test.
Future<void> _tearDown(WidgetTester tester, LowcoAuth auth) async {
  await tester.pumpWidget(const SizedBox.shrink());
  auth.dispose();
}

void main() {
  group('LowcoAuthProvider', () {
    testWidgets('of() throws and maybeOf() returns null without a provider', (tester) async {
      late BuildContext context;
      await tester.pumpWidget(Builder(builder: (c) {
        context = c;
        return const SizedBox.shrink();
      }));
      expect(() => LowcoAuthProvider.of(context), throwsFlutterError);
      expect(LowcoAuthProvider.maybeOf(context), isNull);
    });

    testWidgets('dependents rebuild when the auth state changes', (tester) async {
      final h = Harness();
      final auth = h.create();
      await tester.pumpWidget(_app(
        auth,
        Builder(builder: (context) {
          final a = LowcoAuthProvider.of(context);
          return Text(a.isLoading ? 'loading' : (a.isAuthenticated ? a.user!.name! : 'signed out'));
        }),
      ));
      expect(find.text('loading'), findsOneWidget);

      await auth.initialize();
      await tester.pump();
      expect(find.text('signed out'), findsOneWidget);

      await auth.loginWithRedirect();
      await tester.pump();
      expect(find.text('Ada Lovelace'), findsOneWidget);

      await _tearDown(tester, auth);
    });
  });

  group('WithAuthenticationRequired', () {
    testWidgets('waits for loading, logs in once, then shows the child', (tester) async {
      final h = Harness();
      final auth = h.create();
      await tester.pumpWidget(_app(auth, _guarded));
      await tester.pumpAndSettle();
      expect(find.text('placeholder'), findsOneWidget);
      expect(h.authenticator.calls, isEmpty, reason: 'still loading');

      await auth.initialize();
      await tester.pumpAndSettle();

      expect(h.authenticator.calls, hasLength(1));
      expect(find.text('secret'), findsOneWidget);
      expect(find.text('placeholder'), findsNothing);

      await _tearDown(tester, auth);
    });

    testWidgets('shows the child straight away for a restored session', (tester) async {
      final h = Harness()..store(expiresIn: const Duration(hours: 1), refreshToken: null);
      final auth = h.create();
      await auth.initialize();
      await tester.pumpWidget(_app(auth, _guarded));
      await tester.pumpAndSettle();

      expect(find.text('secret'), findsOneWidget);
      expect(h.authenticator.calls, isEmpty);
      await _tearDown(tester, auth);
    });

    testWidgets('after a cancelled login it keeps the placeholder and does not retry',
        (tester) async {
      final h = Harness();
      h.authenticator.handler = (_) async => throw PlatformException(code: 'CANCELED');
      final auth = h.create();
      await auth.initialize();
      await tester.pumpWidget(_app(auth, _guarded));
      await tester.pumpAndSettle();

      expect(h.authenticator.calls, hasLength(1));
      expect(auth.error, isNull);
      expect(find.text('placeholder'), findsOneWidget);

      await auth.logout(); // notifies again while still signed out
      await tester.pumpAndSettle();
      expect(h.authenticator.calls, hasLength(1));
      await _tearDown(tester, auth);
    });

    testWidgets('autoLogin: false never starts a login', (tester) async {
      final h = Harness();
      final auth = h.create();
      await auth.initialize();
      await tester.pumpWidget(_app(
        auth,
        const WithAuthenticationRequired(
          autoLogin: false,
          placeholder: Text('placeholder'),
          child: Text('secret'),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('placeholder'), findsOneWidget);
      expect(h.authenticator.calls, isEmpty);
      await _tearDown(tester, auth);
    });

    testWidgets('signing out after being authenticated triggers the login again', (tester) async {
      final h = Harness()..store(expiresIn: const Duration(hours: 1), refreshToken: null);
      final auth = h.create();
      await auth.initialize();
      await tester.pumpWidget(_app(auth, _guarded));
      await tester.pumpAndSettle();
      expect(find.text('secret'), findsOneWidget);

      h.authenticator.handler = (_) async => throw PlatformException(code: 'CANCELED');
      await auth.logout();
      await tester.pumpAndSettle();

      expect(find.text('placeholder'), findsOneWidget);
      expect(h.authenticator.calls, hasLength(1));
      await _tearDown(tester, auth);
    });
  });

  group('proactive refresh', () {
    testWidgets('fires 60 s before expiry', (tester) async {
      final h = Harness()..store(expiresIn: const Duration(minutes: 10));
      h.server.respond = (_) => tokenResponse(accessToken: 'at_refreshed', refreshToken: 'rt_2');
      final auth = h.create();
      await auth.initialize();
      expect(h.server.requests, isEmpty);

      await tester.pump(const Duration(minutes: 8, seconds: 59));
      expect(h.server.requests, isEmpty);

      await tester.pump(const Duration(seconds: 2));
      expect(h.bodies.single['refresh_token'], 'rt_stored');
      expect(auth.tokens!.accessToken, 'at_refreshed');
      expect(auth.tokens!.refreshToken, 'rt_2');
      expect(h.issued.single.accessToken, 'at_refreshed');
      expect(jsonDecode(h.storage.values[storageKey]!)['access_token'], 'at_refreshed');

      auth.dispose();
    });

    testWidgets('a rejected background refresh signs out without opening the login page',
        (tester) async {
      final h = Harness()..store(expiresIn: const Duration(minutes: 10));
      h.server.respond = (_) => http.Response(jsonEncode({'error': 'invalid_grant'}), 400);
      final auth = h.create();
      await auth.initialize();
      expect(auth.isAuthenticated, isTrue);

      await tester.pump(const Duration(minutes: 9, seconds: 1));
      expect(h.server.requests, hasLength(1));
      expect(auth.isAuthenticated, isFalse);
      expect(h.stored, isNull);
      expect(h.authenticator.calls, isEmpty);

      auth.dispose();
    });

    testWidgets('logout and dispose cancel the timer', (tester) async {
      final h = Harness()..store(expiresIn: const Duration(minutes: 10));
      final auth = h.create();
      await auth.initialize();
      await auth.logout();
      await tester.pump(const Duration(minutes: 20));
      expect(h.server.requests, isEmpty);

      final h2 = Harness()..store(expiresIn: const Duration(minutes: 10));
      final auth2 = h2.create();
      await auth2.initialize();
      auth2.dispose();
      await tester.pump(const Duration(minutes: 20));
      expect(h2.server.requests, isEmpty);

      auth.dispose();
    });
  });
}
