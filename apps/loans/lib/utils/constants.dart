import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:loooans/app/model/menu_model.dart';
import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:user_repository/user_repository.dart';

class Constants {
  static const appName = 'Loooans!';
  static const tagLine = 'Your loans marketplace';

  // screens
  static bool isExpandedScreen = false;
  static bool isMediumScreen = false;
  static bool isCompactScreen = true;
  static bool forceDownloadNativeApp = false;

  static int lastDashboardIndex = 0;
  static const largeScreenDetailBreakPoint = 1500;
  static const detailContainerSize = 500.0;
  static const currencySymbol = '₱';
  static const jwtSecretKey = 'This is secret key';
  static const tokenQueryParamName = 'tok';
  static DateFormat defaultDateFormat = DateFormat('yyyy-MMM-dd');
  static DateFormat defaultDateCompleteMonthFormat = DateFormat('yyyy-MMMM-dd');
  static DateFormat defaultDateFormatExtended =
      DateFormat('yyyy-MMM-dd HH:mm:ss');
  static DateFormat defaultDateYearMonthFormat = DateFormat('yyyy-MMMM');
  static DateFormat defaultDateMonthFormat = DateFormat('MMM');
  static DateFormat defaultDateFormatWithDay = DateFormat('EEE yyyy-MM-dd');
  static DateFormat westernDateFormatWithDay = DateFormat('EEEE MMMM dd, yyyy');
  static DateFormat westernDateFormat = DateFormat('MMMM dd, yyyy');
  static DateFormat westernDateYearMonthFormat = DateFormat('MMMM yyyy');
  static DateFormat defaultDateFormatWithDayExtended =
      DateFormat('EEEE yyyy-MMM-dd HH:mm:ss');
  static NumberFormat defaultCurrencyFormat =
      NumberFormat('${Constants.currencySymbol} ###,###,###,###,###,##0.00');
  static NumberFormat defaultCurrencyFormatOptionalDecimal =
      NumberFormat('${Constants.currencySymbol} ###,###,###,###,###,##0.##');
  static NumberFormat defaultNumberFormat =
      NumberFormat('###,###,###,###,###,###.##');

  static List<MenuModel> allMenu({
    required BuildContext context,
  }) {
    return [
      const MenuModel(
        title: 'Dashboard',
        logoPath: 'svg/dashboard.svg',
        redirectPath: Paths.dashboard,
      ),
      MenuModel(
        title: 'Products',
        logoPath: 'svg/cash.svg',
        redirectPath: '${Paths.index}?sec=offers',
        show: AuthenticationService.instance.user.userRole == UserRole.admin,
      ),
      const MenuModel(
        title: 'Borrowers',
        logoPath: 'svg/user.svg',
        redirectPath: '${Paths.index}?sec=borrowers',
      ),
      const MenuModel(
        title: 'Users',
        logoPath: 'svg/user.svg',
        redirectPath: '${Paths.index}?sec=users',
      ),
      const MenuModel(
        title: 'Loans',
        logoPath: 'svg/cash.svg',
        redirectPath: '${Paths.index}?sec=clients',
      ),
      MenuModel(
        title: 'Reports',
        logoPath: 'svg/size.svg',
        redirectPath: '${Paths.index}?sec=reports',
        show: AuthenticationService.instance.user.userRole == UserRole.admin,
      ),
    ];
  }

  static List<String> myLoansHeaders = [
    'Date',
    'Provider',
    'Amount',
    'Status',
  ];

  static List<String> loanClientsHeaders = [
    'Date',
    'Name',
    'Amount',
    'Status',
  ];

  static List<String> loanClientsCompleteHeaders = [
    'Date',
    'Due date',
    'Loan type',
    'Name',
    'Amount',
    'Amortization',
    'Status',
  ];

  static List<String> loanScheduleHeaders = [
    'Date',
    'Amortization',
    'Interest',
    'Principal',
  ];

  static List<String> statementOfAccountHeaders = [
    'Date',
    'Number\nof days',
    'Principal\nLoan',
    'Interest\ncharge',
    'Advance\ninterest',
    'Interest\npayment',
    'Principal\npayment',
    // 'Insurance',
    // Savings,
    'Principal\nbalance',
  ];

  static List<String> printLoanScheduleHeaders = [
    '#',
    'Due\ndate',
    'Beginning\nbalance',
    'Interest\npayment',
    'Principal\npayment',
    'Outstanding\nbalance',
  ];

  static List<String> borrowerHeaders = [
    'Name',
    'Address',
    'Phone number',
    'Email address',
    'Member since',
  ];

  static List<String> userHeaders = [
    'Name',
    'Phone number',
    'Email address',
    'Role',
    'Member since',
  ];

  static List<String> borrowerLoansHeader = [
    'Date',
    'Loan',
    'Reason',
    'Amount',
    'Status',
  ];

  static List<String> borrowerPrincipalBorrowersHeader = [
    'Date',
    'Name',
    'Loan',
    'Amount',
    'Status',
  ];
}
