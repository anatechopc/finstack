import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gap/gap.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:loooans/features/products/bloc/product_bloc.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';

class LoanApplicationContinue extends StatelessWidget {
  const LoanApplicationContinue({
    required this.showContinueButton,
    super.key,
    this.onContinuePressed,
  });

  final bool showContinueButton;
  final VoidCallback? onContinuePressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            text:
                'By clicking "continue", you confirm that you have read, understood, acknowledged and that you accept our ',
            style: GoogleFonts.urbanist(
              color: AppColors.black,
            ),
            children: [
              TextSpan(
                text: 'Terms and Conditions',
                style: GoogleFonts.urbanist(
                    color: AppColors.blue,
                    decoration: TextDecoration.underline,),
                recognizer: TapGestureRecognizer()
                  ..onTap = () {
                    final product = context.read<ProductBloc>().selectedProduct;
                    if (product == null || product.termsConditionUrl == null) {
                      return;
                    }

                    AppWidgets.showPdfDialog(
                      context,
                      pdfUri: product.termsConditionUrl!.url,
                    );
                  },
              ),
            ],
          ),
        ),
        if (showContinueButton) ...[
          const Gap(16),
          SizedBox(
            width: double.infinity,
            child: AppWidgets.defaultFilledButton(
              child: Text(
                'Continue',
                style: GoogleFonts.urbanist(
                  fontWeight: FontWeight.w500,
                  fontSize: 16,
                  color: AppColors.green1,
                ),
              ),
              onPressed: onContinuePressed,
            ),
          ),
        ],
      ],
    );
  }
}
