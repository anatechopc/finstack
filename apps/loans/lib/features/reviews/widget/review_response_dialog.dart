import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:gap/gap.dart';
import 'package:loooans/features/reviews/bloc/reviews_bloc.dart';
import 'package:loooans/widgets/app_widgets.dart';
import 'package:review_repository/review_repository.dart';

/// Admin modal to add, edit, or delete the company response on a [review].
/// Mirrors the borrower "Write a review" dialog style. Dispatches
/// [RespondToReviewEvent] / [DeleteReviewResponseEvent] on the ambient
/// [ReviewsBloc] (captured from [context] and re-provided to the dialog route).
Future<void> showReviewResponseDialog(
  BuildContext context, {
  required Review review,
}) {
  final bloc = context.read<ReviewsBloc>();
  return showDialog<void>(
    context: context,
    builder: (_) => BlocProvider.value(
      value: bloc,
      child: ReviewResponseDialog(review: review),
    ),
  );
}

class ReviewResponseDialog extends StatelessWidget {
  const ReviewResponseDialog({required this.review, super.key});

  final Review review;

  @override
  Widget build(BuildContext context) {
    final formKey = GlobalKey<FormBuilderState>(debugLabel: 'review_response');
    final isEditing = review.hasResponse;

    return AlertDialog(
      title: Text(
        isEditing ? 'Edit response' : 'Respond to review',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      content: FormBuilder(
        key: formKey,
        child: SizedBox(
          width: 600,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                review.userFullName,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Gap(4),
              Text(
                review.message,
                style: const TextStyle(fontSize: 12),
              ),
              const Gap(16),
              AppWidgets.defaultFormBuilderTextField(
                name: 'response',
                label: 'Message',
                hintText: 'Write your response to this review',
                initialValue: review.response,
                maxLines: 5,
                validator: FormBuilderValidators.required(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (isEditing)
          SizedBox(
            width: double.infinity,
            child: AppWidgets.defaultOutlinedButton(
              child: const Text('Delete response'),
              onPressed: () {
                context
                    .read<ReviewsBloc>()
                    .add(DeleteReviewResponseEvent(review: review));
                Navigator.of(context, rootNavigator: true).pop();
              },
            ),
          ),
        SizedBox(
          width: double.infinity,
          child: AppWidgets.defaultFilledButton(
            child: const Text('Send'),
            onPressed: () {
              if (formKey.currentState?.saveAndValidate() ?? false) {
                final response =
                    formKey.currentState!.value['response'] as String;
                context.read<ReviewsBloc>().add(
                      RespondToReviewEvent(
                        review: review,
                        response: response,
                      ),
                    );
                Navigator.of(context, rootNavigator: true).pop();
              }
            },
          ),
        ),
      ],
    );
  }
}
