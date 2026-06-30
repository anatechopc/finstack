import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loooans/features/registration/widgets/register_screen_form_users_widget.dart';

import '../../helpers/helpers.dart';

void main() {
  group('RegisterScreenFormUsersWidget — Business name visibility', () {
    testWidgets('is hidden in team-member mode (staff invite)', (tester) async {
      await tester.pumpApp(
        Scaffold(
          body: RegisterScreenFormUsersWidget(
            isAdminCreating: true,
            isTeamMemberMode: true,
            showTermsAndConditions: false,
            disableWidthConstraints: true,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Business name(optional)'), findsNothing);
    });

    testWidgets('is shown in borrower mode', (tester) async {
      await tester.pumpApp(
        Scaffold(
          // isTeamMemberMode defaults to false → borrower mode.
          body: RegisterScreenFormUsersWidget(
            isAdminCreating: true,
            showTermsAndConditions: false,
            disableWidthConstraints: true,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Business name(optional)'), findsOneWidget);
    });
  });
}
