import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:loooans/features/loans/bloc/loans_bloc.dart';
import 'package:loooans/features/products/screen/loan_schedule_widget.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';
import 'package:pdfrx/pdfrx.dart';

void showOfferDialog(
  BuildContext context, {
  required String purpose,
  String? pdfUri,
}) {
  if (purpose == 'payment_schedule') {
    showDialog(
      context: context,
      builder: (context) {
        // height is used for schedule item widget height
        // 20 is the number of items
        // 24 is the height set per item
        var height = (20 * 24).toDouble();

        if (height > 600) {
          height = 600;
        }

        final screenHeight = MediaQuery.sizeOf(context).height;

        if (screenHeight < 800) {
          // this height computation is good until screenHeight=600
          height = screenHeight - (screenHeight * 0.50);
        }

        return AlertDialog(
          backgroundColor: AppColors.green1,
          scrollable: true,
          title: const Text(
            'Loan payment schedule',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 24,
            ),
          ),
          content: LoanScheduleWidget(
            forDialogHeight: height,
            amortization: context.read<LoansBloc>().monthlyAmortization,
            schedules: context.read<LoansBloc>().clientLoanSchedules,
            completeTerm: /*productView.completeTerm*/ '6 months',
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: AppWidgets.defaultFilledButton(
                child: const Text(
                  'Close',
                  style: TextStyle(color: AppColors.green1),
                ),
                onPressed: () {
                  Navigator.of(context, rootNavigator: true).pop();
                },
              ),
            ),
          ],
        );
      },
    );
  } else if (purpose == 'terms') {
    if (pdfUri != null) {
      final controller = PdfViewerController();
      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            backgroundColor: AppColors.green1,
            content: SizedBox(
              width: 1000,
              height: 600,
              child: PdfViewer.uri(
                Uri.parse(pdfUri),
                params: PdfViewerParams(
                  loadingBannerBuilder: (
                      context,
                      bytesDownloaded,
                      totalBytes,
                      ) {
                    return Center(
                      child: CircularProgressIndicator(
                        // totalBytes may not be available on certain case
                        value: totalBytes != null
                            ? bytesDownloaded / totalBytes
                            : null,
                        backgroundColor: Colors.black,
                      ),
                    );
                  },
                  viewerOverlayBuilder: (context, size, handleLinkTap) => [
                    GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      // Your code here:
                      onDoubleTap: () {
                        controller.zoomUp(loop: true);
                      },
                      // If you use GestureDetector on viewerOverlayBuilder, it breaks link-tap handling
                      // and you should manually handle it using onTapUp callback
                      onTapUp: (details) {
                        handleLinkTap(details.localPosition);
                      },
                      // Make the GestureDetector covers all the viewer widget's area
                      // but also make the event go through to the viewer.
                      child: IgnorePointer(
                        child:
                        SizedBox(width: size.width, height: size.height),
                      ),
                    ),
                    PdfViewerScrollThumb(
                      controller: controller,
                      thumbSize: const Size(40, 25),
                      thumbBuilder:
                          (context, thumbSize, pageNumber, controller) =>
                          ColoredBox(
                            color: Colors.black,
                            // Show page number on the thumb
                            child: Center(
                              child: Text(
                                pageNumber.toString(),
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          ),
                    ),
                    // Add horizontal scroll thumb on viewer's bottom
                    PdfViewerScrollThumb(
                      controller: controller,
                      orientation: ScrollbarOrientation.bottom,
                      thumbSize: const Size(80, 30),
                      thumbBuilder:
                          (context, thumbSize, pageNumber, controller) =>
                          const ColoredBox(
                            color: Colors.red,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }
  }
}
