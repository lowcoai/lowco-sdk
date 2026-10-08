import 'package:lowcoai_lowcodb/lowcoai_lowcodb.dart';

Future<void> main() async {
  final client = LowcodbClient(token: '<token-or-api-key>', orgId: 'org_123');
  try {
    final base = await client.createBase(const Base(name: 'crm', baseType: 'internal'));
    await client.createRecord(base.schema!, 'leads', {'name': 'Ada', 'status': 'open'});

    final open = await client.listRecords(
      base.schema!,
      'leads',
      const ListParams(filter: "status='open'", size: 50),
    );
    print('open leads: ${open.length}');
  } on LowcodbException catch (e) {
    print('lowcodb error ${e.statusCode}: ${e.message}');
  } finally {
    client.close();
  }
}
