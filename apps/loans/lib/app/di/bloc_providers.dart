import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:loooans/features/authentication/bloc/authentication_bloc.dart';
import 'package:loooans/features/bank_details/bloc/bank_details_bloc.dart';
import 'package:loooans/features/capital/bloc/capital_bloc.dart';
import 'package:loooans/features/cash_pool/bloc/cash_pool_bloc.dart';
import 'package:loooans/features/chat/bloc/conversations_bloc.dart';
import 'package:loooans/features/companies/bloc/company_bloc.dart';
import 'package:loooans/features/loans/bloc/additional_loan_bloc.dart';
import 'package:loooans/features/loans/bloc/loan_settlement_bloc.dart';
import 'package:loooans/features/loans/bloc/loans_bloc.dart';
import 'package:loooans/features/loans/bloc/payment_bloc.dart';
import 'package:loooans/features/payment_center/bloc/payment_center_bloc.dart';
import 'package:loooans/features/products/bloc/product_bloc.dart';
import 'package:loooans/features/registration/bloc/registration_bloc.dart';
import 'package:loooans/features/reports/bloc/reports_bloc.dart';
import 'package:loooans/features/reviews/bloc/reviews_bloc.dart';
import 'package:loooans/features/search/bloc/search_bloc.dart';
import 'package:loooans/features/users/bloc/user_bloc.dart';

class AppBlocProviders extends StatelessWidget {
  const AppBlocProviders({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: const [
        BlocProvider(
          create: UserBloc.new,
          lazy: false,
        ),
        BlocProvider(create: RegistrationBloc.new),
        BlocProvider(
          create: AuthenticationBloc.new,
          lazy: false,
        ),
        BlocProvider(create: ProductBloc.new),
        BlocProvider(create: LoansBloc.new),
        BlocProvider(create: PaymentBloc.new),
        BlocProvider(create: LoanSettlementBloc.new),
        BlocProvider(create: AdditionalLoanBloc.new),
        BlocProvider(create: ReportsBloc.new),
        BlocProvider(create: ReviewsBloc.new),
        BlocProvider(create: CompanyBloc.new),
        BlocProvider(create: CapitalBloc.new),
        BlocProvider(create: CashPoolBloc.new),
        BlocProvider(create: PaymentCenterBloc.new),
        BlocProvider(create: BankDetailsBloc.new),
        BlocProvider(create: ConversationsBloc.new),
        BlocProvider(create: SearchBloc.new),
      ],
      child: child,
    );
  }
}
