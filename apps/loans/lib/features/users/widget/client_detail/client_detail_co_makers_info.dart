import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:loooans/features/loans/bloc/loans_bloc.dart';
import 'package:loooans/widgets/app_widgets.dart';

class ClientDetailCoMakersInfo extends StatelessWidget {
  const ClientDetailCoMakersInfo({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LoansBloc, LoansState>(
      buildWhen: (prev, next) {
        return next.status == LoansStatus.selected;
      },
      builder: (context, state) {
        if (state.status != LoansStatus.selected) {
          return Container();
        }

        final coMakers = context.read<LoansBloc>().selectedLoanCoMakers;

        if (coMakers.isEmpty) {
          return Container();
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Co-makers Information',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            if (coMakers.isNotEmpty) ...[
              const Gap(16),
              for (final (index, coMaker) in coMakers.indexed)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppWidgets.separatedItem(
                      name: 'Name',
                      description: coMaker.completeNameEasternOrder,
                      index: index + 1,
                      showIndexPlaceholder: true,
                    ),
                    const Gap(4),
                    AppWidgets.separatedItem(
                      name: 'Mobile number',
                      description: coMaker.mobileNumber,
                      showIndexPlaceholder: true,
                    ),
                    const Gap(4),
                    AppWidgets.separatedItem(
                      name: 'Email address',
                      description: coMaker.emailAddress,
                      showIndexPlaceholder: true,
                    ),
                    const Gap(16),
                  ],
                ),
            ],
          ],
        );
      },
    );
  }
}
