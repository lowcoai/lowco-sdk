import 'package:lowcoai_flux/lowcoai_flux.dart';

Future<void> main() async {
  final flux = FluxClient(token: '<token-or-api-key>', orgId: 'org_123');

  flux.onState((state) => print('flux: ${state.name}'));
  flux.onError((error) => print('flux error: $error'));

  // Subscribes made before the socket opens are kept and sent once it does.
  final leads = flux.subscribe('tables:leads');
  leads.bind('row.created', (data, message) => print('new row: $data'));

  // Only some events of a busy schema channel.
  flux.subscribe('channel:<schema>', events: ['messages.*', 'notifications.*']);

  flux.connect();
  await flux.states.firstWhere((state) => state == ConnectionState.connected);

  leads.sendMessage('ping', {'hello': 'world'});

  await Future<void>.delayed(const Duration(seconds: 30));
  flux.disconnect();
}
