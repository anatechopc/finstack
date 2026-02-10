import 'package:loan_repository/src/model/additional_loan_amount_entity.dart';
import 'package:loan_repository/src/model/loan_status.dart';
import 'package:loooans_helpers/data_helpers.dart';

class AdditionalLoanAmount extends AdditionalLoanAmountEntity
    implements BaseModel<AdditionalLoanAmountEntity> {

  AdditionalLoanAmount() : super();

  factory AdditionalLoanAmount.create({
    required String loanId,
    required double amount,
    required double additionalCharges,
    required double advanceCharges,
    required double deductions,
    required ImageUrl selfiePhotoUrl,
    required ImageUrl signatureUrl,
    String? description,
    List<FileUrl> uploadedFilesUrls = const [],
    LoanStatus status = LoanStatus.pending,
  }) {
    final now = DateTime.timestamp();

    return AdditionalLoanAmount()
      ..createdAt = now
      ..updatedAt = now
      ..id = NO_ID
      ..loanId = loanId
      ..amount = amount
      ..additionalCharges = additionalCharges
      ..advanceCharges = advanceCharges
      ..deductions = deductions
      ..description = description
      ..uploadedFilesUrls = uploadedFilesUrls
      ..selfiePhotoUrl = selfiePhotoUrl
      ..signatureUrl = signatureUrl
      ..status = status;
  }
  @override
  AdditionalLoanAmountEntity toEntity() {
    return this;
  }
}
