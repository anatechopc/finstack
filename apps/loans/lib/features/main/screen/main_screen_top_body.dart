import 'package:flutter/material.dart';
import 'package:loooans/features/loans/screens/loans_screen.dart';
import 'package:loooans/features/main/widget/dashboard_top_body.dart';
import 'package:loooans/features/main/widget/dashboard_top_body_admin.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/utils/screen_helpers.dart';

class MainScreenTopBody extends StatelessWidget {

  const MainScreenTopBody({
    required this.section, super.key,
    this.id,
  });
  final String? section;
  final String? id;

  @override
  Widget build(BuildContext context) {
    if (AuthenticationService.instance.isAdmin) {
      return DashboardTopBodyAdmin(
        isReportSection: section == 'reports',
      );
    }

    if (section == 'loans') {
      return LoansScreen(
        loanId: id,
      );
    }

    final screenSizeLessMedium =
        getScreenSize(context: context).index <= ScreenSize.medium.index;

    return Container(
      color:
          section == 'karma' && screenSizeLessMedium ? AppColors.black : null,
      child: DashboardTopBody(
        isKarmaSection: section == 'karma',
      ),
    );
  }
}
