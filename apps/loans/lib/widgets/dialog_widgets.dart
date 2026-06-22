import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:loooans/features/loans/screens/additional_loan_detail_screen.dart';
import 'package:loooans/features/registration/widgets/register_screen_form_providers_widget.dart';
import 'package:loooans/features/users/screens/add_user_widget.dart';
import 'package:loooans/features/users/screens/loan_client_detail.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/button_widgets.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:user_loan_view_repository/user_loan_view_repository.dart';

class DialogWidgets {
  static void showDefaultLoadingDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return const Center(
          child: SizedBox(
            // decoration: BoxDecoration(
            //   color: AppColors.black,
            //   borderRadius: BorderRadius.circular(16),
            // ),
            // padding: EdgeInsets.all(16),
            width: 56,
            height: 56,
            child: CircularProgressIndicator(),
          ),
        );
      },
      barrierDismissible: false,
    );
  }

  static void showDefaultSimpleDialog(
    BuildContext context, {
    required String content,
    String title = 'Attention!',
    List<Widget> actions = const [],
  }) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            ...actions,
            SizedBox(
              // width: double.infinity,
              child: ButtonWidgets.defaultOutlinedButton(
                onPressed: () {
                  Navigator.of(context, rootNavigator: true).pop();
                },
                child: const Text('OK'),
              ),
            ),
          ],
        );
      },
      barrierDismissible: false,
    );
  }

  static void showPdfDialog(
    BuildContext context, {
    String? pdfUri,
    Map<String, Uint8List>? tempPdfBytes,
  }) {
    if (pdfUri != null || tempPdfBytes != null) {
      final controller = PdfViewerController();
      final params = PdfViewerParams(
        loadingBannerBuilder: (
          context,
          bytesDownloaded,
          totalBytes,
        ) {
          return Center(
            child: CircularProgressIndicator(
              // totalBytes may not be available on certain case
              value: totalBytes != null ? bytesDownloaded / totalBytes : null,
              backgroundColor: Colors.black,
            ),
          );
        },
        errorBannerBuilder: (context, err, stackTrace, pdfRef) {
          var errMessage = 'Something went wrong. Cannot open pdf';

          if (err is PdfPasswordException) {
            errMessage += ' with password';
          }

          return Center(
            child: Text(
              errMessage,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w500,
              ),
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
              child: SizedBox(width: size.width, height: size.height),
            ),
          ),
          PdfViewerScrollThumb(
            controller: controller,
            thumbSize: const Size(40, 25),
            thumbBuilder: (context, thumbSize, pageNumber, controller) =>
                Container(
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
            thumbBuilder: (context, thumbSize, pageNumber, controller) =>
                Container(
              color: Colors.red,
            ),
          ),
        ],
      );

      try {
        showDialog(
          context: context,
          builder: (context) {
            return AlertDialog(
              content: SizedBox(
                width: 1000,
                height: 600,
                child: pdfUri != null
                    ? PdfViewer.uri(
                        Uri.parse(pdfUri),
                        controller: controller,
                        params: params,
                      )
                    : PdfViewer.data(
                        tempPdfBytes!.values.first,
                        sourceName: tempPdfBytes.keys.first,
                        params: params,
                      ),
              ),
            );
          },
        );
      } catch (err) {
        debugPrint('Show PDF error: $err');
      }
    }

    throw Exception('PdfUri and TempPdfBytes cannot be null at the same time');
  }

  static Future<void> showLoanClientDetailsDialog(
    BuildContext context, {
    required String userId,
    UserLoanView? userLoanView,
    String? loanId,
    String? productId,
  }) {
    final width = MediaQuery.of(context).size.width;
    final maxWidth = width * 0.9;
    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          contentPadding: const EdgeInsets.all(24),
          content: Container(
            width: maxWidth,
            // height: 1000,
            constraints: BoxConstraints(maxHeight: 1000, maxWidth: maxWidth),
            child: LoanClientDetail(
              userLoanView: userLoanView,
              loanId: loanId,
              productId: productId,
              userId: userId,
            ),
          ),
        );
      },
    );
  }

  static Future<void> showAdditionalLoanDetailDialog(
    BuildContext context, {
    required String additionalLoanId,
  }) {
    final width = MediaQuery.of(context).size.width;
    final maxWidth = width * 0.3;
    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          contentPadding: const EdgeInsets.all(24),
          content: Container(
            width: maxWidth,
            constraints: BoxConstraints(maxHeight: 250, maxWidth: maxWidth),
            child: AdditionalLoanDetailScreen(
              additionalLoanId: additionalLoanId,
              isDialog: true,
            ),
          ),
        );
      },
    );
  }

  static Future<void> showAddUserWidget(
    BuildContext context, {
    Color backgroundColor = AppColors.green1,
    bool withLoanApplication = false,
    bool withExtendedUserDetailInputs = false,
    bool? allowAddOns,
    bool scrollable = false,
    bool forCompanyUser = false,
    bool isTeamMember = false,
  }) {
    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: backgroundColor,
          scrollable: scrollable,
          content: !forCompanyUser ? AddUserWidget(
            withLoanApplication: withLoanApplication,
            withExtendedUserDetailInputs: withExtendedUserDetailInputs,
            allowAddOns: allowAddOns,
            isTeamMember: isTeamMember,
          ) : RegisterScreenFormProvidersWidget(
            registerCompanyManagedUser: true,
            defaultInputColor: AppColors.lightBlack,
            showAsDialog: true,
          ),
        );
      },
    );
  }
}
