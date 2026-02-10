import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:loooans/features/users/bloc/user_bloc.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/widgets/app_widgets.dart';

class ClientDetailBasicInfo extends StatelessWidget {
  const ClientDetailBasicInfo({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<UserBloc, UserState>(
      buildWhen: (prev, next) {
        return next.status == UserStatus.selected;
      },
      builder: (context, state) {
        if (state.status != UserStatus.selected) {
          return Container();
        }

        final user = context.read<UserBloc>().user;
        final address = context.read<UserBloc>().address;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Basic Information',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            if (state.status == UserStatus.selected) ...[
              const Gap(16),
              AppWidgets.separatedItem(
                name: 'Name',
                description: user.completeNameEasternOrder,
              ),
              const Gap(16),
              AppWidgets.separatedItem(
                name: 'Address',
                description: address.toString(),
              ),
              const Gap(4),
              AppWidgets.separatedItem(
                name: 'Birthdate',
                description: user.birthDate.toDefaultDateFormat(),
              ),
              const Gap(4),
              AppWidgets.separatedItem(
                name: 'Mobile number',
                description: user.mobileNumber,
              ),
              const Gap(4),
              AppWidgets.separatedItem(
                name: 'Facebook profile',
                description: user.facebookProfileUrl ?? 'N/A',
              ),
            ],
          ],
        );
      },
    );
  }
}
