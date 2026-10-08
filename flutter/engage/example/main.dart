import 'package:flutter/material.dart';
import 'package:lowcoai_engage/lowcoai_engage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LowcoAnalytics.instance.init(
    EngageConfig(
      apiKey: '<api-key>',
      orgId: 'org_123',
      autoTrack: true, // web: capture utm_* / click ids from the page URL
      onError: (error) => debugPrint('engage: $error'),
    ),
  );

  // Deep link that opened the app (e.g. from package:app_links):
  await LowcoAnalytics.instance.captureAttribution(
    Uri.parse('myapp://promo?utm_source=newsletter&utm_campaign=fall'),
  );

  runApp(const DemoApp());
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorObservers: [LowcoAnalyticsObserver()], // page_view per named route
      routes: {
        '/': (_) => const HomePage(),
        '/pricing': (_) => const Scaffold(body: Center(child: Text('Pricing'))),
      },
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton(
              onPressed: () => LowcoAnalytics.instance.track('signup_completed', {'plan': 'pro'}),
              child: const Text('Track signup'),
            ),
            TextButton(
              onPressed: () => LowcoAnalytics.instance.identifyUser('user_123', {
                'email': 'alice@example.com',
              }),
              child: const Text('Identify'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pushNamed('/pricing'),
              child: const Text('Pricing'),
            ),
          ],
        ),
      ),
    );
  }
}
