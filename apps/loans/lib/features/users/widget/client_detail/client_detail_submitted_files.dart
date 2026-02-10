import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:loooans/features/loans/bloc/loans_bloc.dart';
import 'package:loooans/widgets/app_widgets.dart';
import 'package:loooans/widgets/file_viewer_widget.dart';

class ClientDetailSubmittedFiles extends StatelessWidget {
  const ClientDetailSubmittedFiles({super.key});

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

        final selectedLoan = context.read<LoansBloc>().selectedLoan;

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(
                  child: Text(
                    'Submitted files',
                    maxLines: 2,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
                const Gap(8),
                InkWell(
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (context) {
                        return AlertDialog(
                          content: SizedBox(
                            width: 1000,
                            height: 800,
                            child: FileViewerWidget(
                              items: selectedLoan.requirements,
                            ),
                          ),
                        );
                      },
                    );
                  },
                  child: const Icon(Icons.visibility_rounded),
                ),
              ],
            ),
            const Gap(16),
            ...selectedLoan.requirements
                .groupListsBy((req) => req.name)
                .keys
                .map((key) => AppWidgets.legendItem(title: key)),
          ],
        );
      },
    );
  }
}
