// NOTE: FOR SOME REASON, PRINTING FOR WEB WAS WORKING AGAIN... I DON'T KNOW
// WHY.. .FOR NOW, COMMENTED OUT THE CODE. THE COMMENTED CODE IS THROWING
// AN ERROR WHEN BUILDING NATIVE APPS LIKE ANDROID AND IOS.


import 'package:address_repository/address_repository.dart';
import 'package:collection/collection.dart';
import 'package:company_repository/company_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/features/reports/models/soa_model.dart';
import 'package:loooans/utils/constants.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:pdf/pdf.dart';

// if (dart.library.html) 'package:printing/printing_web.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:product_repository/product_repository.dart';
import 'package:user_repository/user_repository.dart';

part 'pdf_generator_build_pdf.dart';

part 'pdf_generator_build_soa.dart';

part 'pdf_generator_ext_notes.dart';

part 'pdf_generator_ext_widgets.dart';

class PdfGenerator {
  static Future<void> generatePdf({
    required List<LoanSchedule> schedules, required Loan loan, required Product product, User? user,
    Address? userAddress,
    Company? company,
    Address? companyAddress,
  }) {
    // if (kIsWeb) {
    //   return PrintingPlugin().layoutPdf(
    //     null,
    //     // [onLayout] will be called multiple times
    //     // when the user changes the printer or printer settings
    //     (PdfPageFormat format) {
    //       // Any valid Pdf document can be returned here as a list of int
    //       const margin = 1 * PdfPageFormat.cm;
    //       return _buildPdf(
    //         // format.copyWith(
    //         //   height: PdfPageFormat.a4.width,
    //         //   width: PdfPageFormat.a4.height,
    //         //   marginLeft: margin,
    //         //   marginTop: margin,
    //         //   marginRight: margin,
    //         //   marginBottom: margin,
    //         // ),
    //         // format,
    //         PdfPageFormat.a4,
    //         user: user,
    //         schedules: schedules,
    //         loan: loan,
    //         company: company,
    //         userAddress: userAddress,
    //         companyAddress: companyAddress,
    //         product: product,
    //       );
    //     },
    //     'print',
    //     PdfPageFormat.a4,
    //     true,
    //     true,
    //     OutputType.generic,
    //     false,
    //   );
    // }

    return Printing.layoutPdf(
      // [onLayout] will be called multiple times
      // when the user changes the printer or printer settings
      onLayout: (PdfPageFormat format) {
        // Any valid Pdf document can be returned here as a list of int
        // const margin = 1 * PdfPageFormat.cm;
        return _buildPdf(
          // format.copyWith(
          //   height: PdfPageFormat.a4.width,
          //   width: PdfPageFormat.a4.height,
          //   marginLeft: margin,
          //   marginTop: margin,
          //   marginRight: margin,
          //   marginBottom: margin,
          // ),
          // format,
          PdfPageFormat.a4,
          user: user,
          schedules: schedules,
          loan: loan,
          company: company,
          userAddress: userAddress,
          companyAddress: companyAddress,
          product: product,
        );
      },
    );
  }

  static Future<void> generatePdfSoa({
    required SOAModel soaModel,
    Company? company,
    Address? companyAddress,
  }) {
    // if (kIsWeb) {
    //   return PrintingPlugin().layoutPdf(
    //     null,
    //     // [onLayout] will be called multiple times
    //     // when the user changes the printer or printer settings
    //     (PdfPageFormat format) {
    //       // Any valid Pdf document can be returned here as a list of int
    //       const margin = 1 * PdfPageFormat.cm;
    //       return _buildPdfSoa(
    //         // format.copyWith(
    //         //   height: PdfPageFormat.a4.width,
    //         //   width: PdfPageFormat.a4.height,
    //         //   marginLeft: margin,
    //         //   marginTop: margin,
    //         //   marginRight: margin,
    //         //   marginBottom: margin,
    //         // ),
    //         // format,
    //         PdfPageFormat.a4,
    //         soaModel: soaModel,
    //         company: company,
    //         companyAddress: companyAddress,
    //       );
    //     },
    //     'print',
    //     PdfPageFormat.a4,
    //     true,
    //     true,
    //     OutputType.generic,
    //     false,
    //   );
    // }

    return Printing.layoutPdf(
      // [onLayout] will be called multiple times
      // when the user changes the printer or printer settings
      onLayout: (PdfPageFormat format) {
        // Any valid Pdf document can be returned here as a list of int
        // const margin = 1 * PdfPageFormat.cm;
        return _buildPdfSoa(
          // format.copyWith(
          //   height: PdfPageFormat.a4.width,
          //   width: PdfPageFormat.a4.height,
          //   marginLeft: margin,
          //   marginTop: margin,
          //   marginRight: margin,
          //   marginBottom: margin,
          // ),
          // format,
          PdfPageFormat.a4,
          soaModel: soaModel,
          company: company,
          companyAddress: companyAddress,
        );
      },
    );
  }

  static Future<void> printRemoteFile({
    required String url,
    required String fileName,
  }) {
    // if (kIsWeb) {
    //   return PrintingPlugin().layoutPdf(
    //     null,
    //     // [onLayout] will be called multiple times
    //     // when the user changes the printer or printer settings
    //     (PdfPageFormat format) {
    //       // Any valid Pdf document can be returned here as a list of int
    //       const margin = 1 * PdfPageFormat.cm;
    //       return _buildPdf(
    //         // format.copyWith(
    //         //   height: PdfPageFormat.a4.width,
    //         //   width: PdfPageFormat.a4.height,
    //         //   marginLeft: margin,
    //         //   marginTop: margin,
    //         //   marginRight: margin,
    //         //   marginBottom: margin,
    //         // ),
    //         // format,
    //         PdfPageFormat.a4,
    //         user: user,
    //         schedules: schedules,
    //         loan: loan,
    //         company: company,
    //         userAddress: userAddress,
    //         companyAddress: companyAddress,
    //         product: product,
    //       );
    //     },
    //     'print',
    //     PdfPageFormat.a4,
    //     true,
    //     true,
    //     OutputType.generic,
    //     false,
    //   );
    // }

    Future<Uint8List> downloadRemoteFile(String url) async {
      return http.get(Uri.parse(url)).then((response) {
        if (response.statusCode == 200) {
          return response.bodyBytes;
        } else {
          throw Exception('Failed to download file: ${response.body}');
        }
      });
    }

    try {
      return Printing.layoutPdf(
        // [onLayout] will be called multiple times
        // when the user changes the printer or printer settings
        onLayout: (PdfPageFormat format) async {
          // Any valid Pdf document can be returned here as a list of int
          final pdfTheme = pw.ThemeData.withFont(
              base: await PdfGoogleFonts.robotoRegular(),
              bold: await PdfGoogleFonts.robotoBold(),
              boldItalic: await PdfGoogleFonts.robotoBoldItalic(),
              italic: await PdfGoogleFonts.robotoItalic(),
              icons: await PdfGoogleFonts.robotoRegular(),);
// Create the Pdf document
          final doc = pw.Document(theme: pdfTheme);
          final image = await downloadRemoteFile(url).then(
                (Uint8List bytes) {
              return bytes;
            },
          ).then(pw.MemoryImage.new);

          doc.addPage(
            pw.Page(
              build: (context) {
                return pw.Center(
                  child: pw.Image(
                    image,
                  ),
                );
              },
            ),
          );

          return doc.save();
        },
        name: fileName,
      );
    } catch (e) {
      debugPrint('Error printing remote file: $e');
    }

    return Future.value();
  }
}
