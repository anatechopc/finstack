import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:loooans/features/loans/bloc/loans_bloc.dart';
import 'package:loooans/features/loans/model/loan_simple.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';

class ClientDetailLoanSelector extends StatelessWidget {
  const ClientDetailLoanSelector({
    required this.loanId,
    required this.onLoanSelected,
    super.key,
  });

  final String? loanId;
  final void Function({
    required String loanId,
    required String productId,
  }) onLoanSelected;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LoansBloc, LoansState>(
      buildWhen: (prev, next) {
        return next.status == LoansStatus.allUserLoansRetrieved;
      },
      builder: (context, state) {
        final allLoans = context.read<LoansBloc>().userLoans;
        LoanSimple? initialValue;

        if (allLoans.isNotEmpty) {
          if (loanId != null) {
            initialValue = allLoans.singleWhereOrNull(
              (loan) => loan.loanId == loanId,
            );
          } else {
            initialValue = allLoans.first;
          }
        }

        return AppWidgets.defaultFormBuilderDropdown(
          name: 'loan',
          label: 'Type',
          items: allLoans
              .map(
                (loan) => DropdownMenuItem(
                  value: loan,
                  child: Text('${loan.loanType} (${loan.status.label})'),
                ),
              )
              .toList(),
          initialValue: initialValue,
          onChanged: (val) {
            if (val == null) {
              return;
            }

            onLoanSelected(
              loanId: val.loanId,
              productId: val.productId,
            );
          },
          dropdownColor: AppColors.white,
        );
      },
    );
  }
}
