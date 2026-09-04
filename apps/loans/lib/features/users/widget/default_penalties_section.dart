import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:loooans/features/companies/bloc/company_bloc.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/penalty_dialog.dart';
import 'package:loooans_helpers/data_helpers.dart';

/// Company default penalties shown on the admin's profile card.
///
/// Every new product starts with these defaults; editing here does not
/// retroactively change products already created. Edits are optimistic:
/// the chip list updates immediately and rolls back if the save fails.
class DefaultPenaltiesSection extends StatefulWidget {
  const DefaultPenaltiesSection({
    super.key,
    this.foregroundColor = AppColors.white,
  });

  final Color foregroundColor;

  @override
  State<DefaultPenaltiesSection> createState() =>
      _DefaultPenaltiesSectionState();
}

class _DefaultPenaltiesSectionState extends State<DefaultPenaltiesSection> {
  late List<Penalty> _penalties = List<Penalty>.of(
    AuthenticationService.instance.company.defaultPenalties,
  );

  @override
  Widget build(BuildContext context) {
    return BlocListener<CompanyBloc, CompanyState>(
      listenWhen: (previous, current) =>
          current.message == CompanyBloc.defaultPenaltiesSavedMessage ||
          current.message == CompanyBloc.defaultPenaltiesFailedMessage,
      listener: (context, state) {
        if (state.status == CompanyStateStatus.error) {
          setState(() {
            _penalties = List<Penalty>.of(
              AuthenticationService.instance.company.defaultPenalties,
            );
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message ?? 'Cannot update default penalties'),
            ),
          );
        } else if (state.status == CompanyStateStatus.success &&
            state.message != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message!)),
          );
        }
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Gap(16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Default penalties',
                style: TextStyle(
                  color: widget.foregroundColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.add_circle_outline,
                  color: widget.foregroundColor,
                ),
                tooltip: 'Add default penalty',
                onPressed: _addPenalty,
              ),
            ],
          ),
          Text(
            'Every new product starts with these. Editing here does not '
            'change products already created.',
            style: TextStyle(color: widget.foregroundColor, fontSize: 12),
          ),
          const Gap(8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _penalties.map((penalty) {
              return Chip(
                label: Text(penalty.chipLabel),
                backgroundColor: AppColors.white,
                onDeleted: () => _removePenalty(penalty),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Future<void> _addPenalty() async {
    final penalty = await showPenaltyDialog(context);
    if (penalty == null || !mounted) {
      return;
    }
    final updated = [..._penalties, penalty];
    setState(() => _penalties = updated);
    context.read<CompanyBloc>().updateDefaultPenalties(updated);
  }

  void _removePenalty(Penalty penalty) {
    final updated = _penalties.where((p) => p.id != penalty.id).toList();
    setState(() => _penalties = updated);
    context.read<CompanyBloc>().updateDefaultPenalties(updated);
  }
}
