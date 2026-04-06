import 'package:flutter_test/flutter_test.dart';
import 'package:face_attendance/main.dart';

void main() {
  testWidgets('App renders login screen', (WidgetTester tester) async {
    await tester.pumpWidget(const FaceAttendanceApp());
    await tester.pumpAndSettle();

    expect(find.text('Face Attendance'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
  });
}
