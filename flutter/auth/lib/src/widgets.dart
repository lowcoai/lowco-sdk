import 'dart:async';

import 'package:flutter/widgets.dart';

import 'lowco_auth.dart';

/// Makes a [LowcoAuth] available to the widget tree and rebuilds dependents
/// whenever it notifies (the React `LowcoAuthProvider` + `useLowcoAuth`).
///
/// ```dart
/// final auth = LowcoAuth(...)..initialize();
/// runApp(LowcoAuthProvider(auth: auth, child: const MyApp()));
///
/// // below it:
/// final auth = LowcoAuthProvider.of(context);
/// ```
class LowcoAuthProvider extends InheritedNotifier<LowcoAuth> {
  const LowcoAuthProvider({super.key, required LowcoAuth auth, required super.child})
      : super(notifier: auth);

  /// The nearest [LowcoAuth]; registers [context] for rebuilds. Throws when
  /// there is no [LowcoAuthProvider] above [context].
  static LowcoAuth of(BuildContext context) {
    final auth = maybeOf(context);
    if (auth == null) {
      throw FlutterError(
        'LowcoAuthProvider.of() called with a context that does not contain a '
        'LowcoAuthProvider.\nWrap your app (or this subtree) in a LowcoAuthProvider.',
      );
    }
    return auth;
  }

  /// Like [of], but returns `null` without a provider.
  static LowcoAuth? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LowcoAuthProvider>()?.notifier;
}

/// Renders [child] only for an authenticated user (the React
/// `withAuthenticationRequired`).
///
/// While the session is loading, or the user is signed out, [placeholder] is
/// shown. Once loading has finished and the user is unauthenticated,
/// `loginWithRedirect()` is started **once** (when [autoLogin] is true); if
/// the user cancels, the placeholder stays up — put a sign-in button in it to
/// retry. After the user has been authenticated, a later sign-out triggers
/// the automatic login again.
class WithAuthenticationRequired extends StatefulWidget {
  const WithAuthenticationRequired({
    super.key,
    required this.child,
    this.placeholder = const SizedBox.shrink(),
    this.autoLogin = true,
  });

  final Widget child;
  final Widget placeholder;
  final bool autoLogin;

  @override
  State<WithAuthenticationRequired> createState() => _WithAuthenticationRequiredState();
}

class _WithAuthenticationRequiredState extends State<WithAuthenticationRequired> {
  bool _loginStarted = false;

  @override
  Widget build(BuildContext context) {
    final auth = LowcoAuthProvider.of(context);
    if (auth.isAuthenticated) {
      _loginStarted = false;
      return widget.child;
    }
    if (widget.autoLogin && !auth.isLoading && !_loginStarted) {
      _loginStarted = true;
      // Not during build: loginWithRedirect notifies listeners synchronously.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !auth.isAuthenticated && !auth.isLoading) {
          unawaited(auth.loginWithRedirect());
        }
      });
    }
    return widget.placeholder;
  }
}
