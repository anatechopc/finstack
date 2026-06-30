import 'package:flutter_test/flutter_test.dart';
import 'package:loooans/features/users/screens/add_user_widget.dart';

void main() {
  group('addUserWidgetTitle', () {
    test('loan-application flow (not extended-details only) → "Add loan"', () {
      expect(
        addUserWidgetTitle(extendedDetailsOnly: false, isTeamMember: false),
        'Add loan',
      );
      // isTeamMember is irrelevant when this is the loan flow.
      expect(
        addUserWidgetTitle(extendedDetailsOnly: false, isTeamMember: true),
        'Add loan',
      );
    });

    test('extended-details flow for a staff invite → "Add team member"', () {
      // Regression: clicking "Add team member" used to open a form titled
      // "Add borrower" because the title ignored isTeamMember.
      expect(
        addUserWidgetTitle(extendedDetailsOnly: true, isTeamMember: true),
        'Add team member',
      );
    });

    test('extended-details flow for a borrower invite → "Add borrower"', () {
      expect(
        addUserWidgetTitle(extendedDetailsOnly: true, isTeamMember: false),
        'Add borrower',
      );
    });
  });
}
