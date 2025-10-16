import 'package:flutter_test/flutter_test.dart';
import 'package:interface_viewer/main.dart';

void main() {
  testWidgets('app builds and shows title', (tester) async {
    await tester.pumpWidget(const TelemetryApp());
    expect(find.text('Telemetry Viewer'), findsOneWidget);
  });
}
