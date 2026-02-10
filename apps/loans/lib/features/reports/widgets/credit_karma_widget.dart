import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:loooans/features/reports/widgets/karma_gauge_widget.dart';
import 'package:loooans/features/users/bloc/user_bloc.dart';
import 'package:loooans/features/users/widget/profile_widget.dart';

class CreditKarmaWidget extends StatelessWidget {
  const CreditKarmaWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const KarmaGaugeWidget(
            expand: true,
            showCredit: true,
          ),
          const Gap(24),
          BlocBuilder<UserBloc, UserState>(
            builder: (context, state) {
              return const ProfileWidget();
            },
          ),
        ],
      ),
    );
  }
}
