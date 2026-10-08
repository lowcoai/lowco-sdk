import 'package:lowcoai_agentx/lowcoai_agentx.dart';

Future<void> main() async {
  final client = AgentxClient(token: '<token-or-api-key>', orgId: 'org_123');
  try {
    final agents = await client.manager.listAgents(const ListParams(size: 10));
    print('agents: ${agents.length} of ${await client.manager.getAgentCount()}');
    if (agents.isEmpty) return;
    final agentId = agents.first.id!;

    final params = MessageSendParams(
      message: A2AMessage(
        role: 'user',
        parts: const [TextPart(text: 'Summarise my open tickets')],
        messageId: DateTime.now().microsecondsSinceEpoch.toString(),
      ),
    );

    // Synchronous call: the reply is a JSON-RPC response.
    final resp = await client.executor.sendMessage(agentId, params);
    if (resp.error != null) {
      print('rpc error ${resp.error!.code}: ${resp.error!.message}');
    } else if (resp.result is Map<String, dynamic>) {
      final reply = A2AMessage.fromJson(resp.result as Map<String, dynamic>);
      print(reply.parts.whereType<TextPart>().map((p) => p.text).join());
    }

    // Streaming call: one event per server-sent event.
    await for (final ev in client.executor.streamMessage(agentId, params)) {
      final msg = tryParseMessage(ev);
      if (msg == null) continue;
      for (final part in msg.parts) {
        switch (part) {
          case TextPart(:final text):
            print(text);
          case FilePart(file: FileWithURI(:final uri)):
            print('file: $uri');
          case FilePart() || DataPart() || UnknownPart():
            print('[${part.kind} part]');
        }
      }
    }
  } on AgentxException catch (e) {
    print('agentx error ${e.statusCode}: ${e.message}');
  } finally {
    client.close();
  }
}
