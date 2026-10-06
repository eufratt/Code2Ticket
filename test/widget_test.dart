import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:code2ticket/main.dart';

void main() {
  testWidgets('Code2TicketApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: Code2TicketApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Code2Ticket'), findsWidgets);
  });
}
