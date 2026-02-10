import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

class ClientDetailReasonForLoan extends StatelessWidget {
  const ClientDetailReasonForLoan({
    required this.reason,
    super.key,
  });

  final String reason;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Reason for loan',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Gap(8),
        Text(
          reason,
          style: const TextStyle(
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
