import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/widgets/message_actions_sheet.dart';

void main() {
  testWidgets('renders the shared message action labels', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => MessageActionsSheet.show(
              context: context,
              actions: const [
                MessageActionItem(
                  label: '复制',
                  icon: Icons.copy,
                  onPressed: _noop,
                ),
              ],
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('复制'), findsOneWidget);
  });
}

void _noop() {}
