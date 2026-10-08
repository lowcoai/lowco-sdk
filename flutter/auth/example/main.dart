import 'package:flutter/material.dart';
import 'package:lowcoai_auth/lowcoai_auth.dart';

final auth = LowcoAuth(
  domain: 'https://api.lowco.ai/v1/identity',
  loginPageUrl: 'https://login.example.com/login', // your hosted lowco login page
  tenantId: '<tenant-id>',
  clientId: '<client-id>',
  redirectUri: 'com.example.app://callback', // registered on the OAuth client, exactly
  onTokens: (tokens) => debugPrint('access token valid until ${tokens.expiresAtTime}'),
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  auth.initialize(); // restore / refresh the stored session
  runApp(LowcoAuthProvider(auth: auth, child: const DemoApp()));
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: WithAuthenticationRequired(
        placeholder: SignInPage(),
        child: HomePage(),
      ),
    );
  }
}

class SignInPage extends StatelessWidget {
  const SignInPage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = LowcoAuthProvider.of(context);
    return Scaffold(
      body: Center(
        child: auth.isLoading
            ? const CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (auth.error != null) Text('Sign-in failed: ${auth.error!.message}'),
                  FilledButton(
                    onPressed: () => auth.loginWithRedirect(appState: {'returnTo': '/'}),
                    child: const Text('Sign in'),
                  ),
                ],
              ),
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = LowcoAuthProvider.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('Hi ${auth.user?.name ?? auth.user?.email ?? ''}'),
        actions: [IconButton(onPressed: auth.logout, icon: const Icon(Icons.logout))],
      ),
      body: Center(
        child: FilledButton(
          onPressed: () async {
            // Refreshed first when it expires within 60 s.
            final token = await auth.getAccessTokenSilently();
            // http.get(apiUrl, headers: {'Authorization': 'Bearer $token'});
            debugPrint('got an access token (${token.length} chars)');
          },
          child: const Text('Call API'),
        ),
      ),
    );
  }
}
