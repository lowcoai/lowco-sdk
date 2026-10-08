/// Official Dart / Flutter client for the lowco integrations-manager.
library;

export 'src/client.dart' show IntegrationsClient;
export 'src/errors.dart' show IntegrationsException;
export 'src/models.dart';
export 'src/query.dart' show PaginationQuery;
export 'src/resources/actions.dart' show ActionsResource;
export 'src/resources/applications.dart' show ApplicationsResource;
export 'src/resources/configurations.dart' show ConfigurationsResource;
export 'src/resources/connections.dart' show ConnectionsResource;
export 'src/resources/mcp.dart' show McpResource;
export 'src/resources/oauth.dart' show OAuthResource;
export 'src/resources/triggers.dart' show TriggersResource;
export 'src/transport.dart' show IntegrationsHttpClient, lowcoBaseUrl, headerOrgId;
