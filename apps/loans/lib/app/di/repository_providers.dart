import 'package:address_repository/address_repository.dart';
import 'package:authentication_repository/authentication_repository.dart';
import 'package:bank_details_repository/bank_details_repository.dart';
import 'package:capital_repository/capital_repository.dart';
import 'package:cash_pool_repository/cash_pool_repository.dart';
import 'package:chat_repository/chat_repository.dart';
import 'package:company_repository/company_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/features/search/firestore_search_index.dart';
import 'package:loooans/features/search/search_index.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:notification_repository/notification_repository.dart';
import 'package:payment_repository/payment_repository.dart';
import 'package:product_repository/product_repository.dart';
import 'package:product_view_repository/product_view_repository.dart';
import 'package:reports_repository/reports_repository.dart';
import 'package:review_repository/review_repository.dart';
import 'package:settings_repository/settings_repository.dart';
import 'package:storage_repository/storage_repository.dart';
import 'package:user_loan_view_repository/user_loan_view_repository.dart';
import 'package:user_repository/user_repository.dart';

class AppRepositoryProviders extends StatelessWidget {
  const AppRepositoryProviders({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider(create: (context) => UserRepository()),
        RepositoryProvider(create: (context) => AuthenticationRepository()),
        RepositoryProvider(create: (context) => StorageRepository()),
        RepositoryProvider(create: (context) => ProductViewRepository()),
        // Registered as the interface, not the implementation: `SearchBloc`
        // reads `SearchIndex`, which is what makes the engine swappable.
        RepositoryProvider<SearchIndex>(
          create: (context) => FirestoreSearchIndex(),
        ),
        RepositoryProvider(create: (context) => ProductRepository()),
        RepositoryProvider(create: (context) => LoanRepository()),
        RepositoryProvider(create: (context) => LoanScheduleRepository()),
        RepositoryProvider(create: (context) => UserLoanViewRepository()),
        RepositoryProvider(create: (context) => CompanyRepository()),
        RepositoryProvider(create: (context) => AddressRepository()),
        RepositoryProvider(create: (context) => ReviewRepository()),
        RepositoryProvider(create: (context) => CapitalRepository()),
        RepositoryProvider(create: (context) => ReportsRepository()),
        RepositoryProvider(create: (context) => NotificationRepository()),
        RepositoryProvider(create: (context) => ChatRoomRepository()),
        RepositoryProvider(create: (context) => TypingService()),
        RepositoryProvider(create: (context) => PaymentRepository()),
        RepositoryProvider(create: (context) => SettingsRepository()),
        RepositoryProvider(create: (context) => CashPoolRepository()),
        RepositoryProvider<BaseRepository<BankDetails>>(
          create: (context) => BankDetailsRepository(),
        ),
      ],
      child: child,
    );
  }
}
