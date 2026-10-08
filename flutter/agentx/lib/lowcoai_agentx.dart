/// Official Dart / Flutter client for the lowco agentx services: the agent
/// manager, knowledge bases and the A2A executor (with SSE streaming).
library;

export 'src/a2a.dart';
export 'src/client.dart' show AgentxClient;
export 'src/constants.dart';
export 'src/errors.dart' show AgentxException;
export 'src/executor.dart' show ExecutorClient, StreamEvent, tryParseMessage;
export 'src/kb.dart' show KBClient;
export 'src/manager.dart' show ManagerClient;
export 'src/models.dart';
export 'src/transport.dart' show ListParams;
