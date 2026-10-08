import 'package:lowcoai_integrations/lowcoai_integrations.dart';

Future<void> main() async {
  final client = IntegrationsClient(token: '<token-or-api-key>', orgId: 'org_123');
  try {
    final apps = await client.applications
        .list(const PaginationQuery(page: 1, limit: 20, tags: 'crm,sales'));
    print('found ${apps.length} applications');

    // Run an action with a stored connection.
    final result = await client.actions.run(
      'action_123',
      const RunActionRequest(
        credentialId: 'conn_456',
        inputBody: {'to': 'alice@example.com', 'subject': 'Hello'},
      ),
    );
    print('result: $result');

    // Start an OAuth flow; redirect the user to `login.url`.
    final login = await client.oauth.login(
      'app_slack',
      const ConnectionCreateRequest(applicationId: 'app_slack', name: 'Slack — Sales workspace'),
    );
    print('redirect to ${login.url}');
  } on IntegrationsException catch (e) {
    print('integrations error ${e.status}: ${e.message} ${e.payload}');
  } finally {
    client.close();
  }
}
