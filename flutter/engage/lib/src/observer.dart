import 'dart:async';

import 'package:flutter/widgets.dart';

import 'analytics.dart';

/// Sends a `page_view` whenever a named route becomes visible — the Flutter
/// equivalent of the browser SDK's `autoTrack` history tracking.
///
/// ```dart
/// MaterialApp(
///   navigatorObservers: [LowcoAnalyticsObserver()],
///   routes: {...},
/// )
/// ```
///
/// The event properties are `{path: <route name>, title: <route name>}`.
/// Routes without a name (most dialogs, bottom sheets and anonymous
/// `MaterialPageRoute`s) are skipped: give pages a `RouteSettings(name: ...)`
/// to track them. Events fired before `LowcoAnalytics.init` completes are
/// dropped.
class LowcoAnalyticsObserver extends NavigatorObserver {
  /// Reports to [analytics], or to [LowcoAnalytics.instance] when omitted.
  LowcoAnalyticsObserver({LowcoAnalytics? analytics}) : _analytics = analytics;

  final LowcoAnalytics? _analytics;

  /// The client events are sent to.
  LowcoAnalytics get analytics => _analytics ?? LowcoAnalytics.instance;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _pageView(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _pageView(newRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _pageView(previousRoute);
  }

  void _pageView(Route<dynamic>? route) {
    final name = route?.settings.name;
    if (name == null || name.isEmpty) return;
    unawaited(analytics.page({'path': name, 'title': name}));
  }
}
