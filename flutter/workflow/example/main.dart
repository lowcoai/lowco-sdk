import 'package:lowcoai_workflow/lowcoai_workflow.dart';

Future<void> main() async {
  final client = WorkflowClient(token: '<token-or-api-key>', orgId: 'org_123');
  try {
    final workflows = await client.workflows.list(const PaginationQuery(page: 1, limit: 20));
    print('workflows: ${workflows.length}');

    // Start a run.
    final run = await client.workflows.run(const RunWorkflowRequest(
      workflowId: 'wf_123',
      inputData: {'orderId': 'o_1'},
      environmentId: 'env_default',
    ));
    print('run: $run');

    // Answer the first open human task.
    final tasks = await client.humanTasks.list(const PaginationQuery(page: 1, limit: 10));
    if (tasks.isNotEmpty) await client.humanTasks.complete(tasks.first.id!, 'approve');

    // Fire the workflow's webhook without waiting for the run to finish.
    await client.webhooks.trigger('wf_123', payload: {'orderId': 'o_2'}, async: true);
  } on WorkflowException catch (e) {
    print('workflow error ${e.status}: ${e.message} ${e.payload}');
  } finally {
    client.close();
  }
}
