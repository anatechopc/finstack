import 'package:json_annotation/json_annotation.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loooans_helpers/data_helpers.dart';

part 'additional_loan_amount_entity.g.dart';

@JsonSerializable()
class AdditionalLoanAmountEntity implements BaseEntity {
  AdditionalLoanAmountEntity();

  factory AdditionalLoanAmountEntity.fromJson(Map<String, dynamic> json) {
    return _$AdditionalLoanAmountEntityFromJson(json);
  }

  AdditionalLoanAmountEntity._({
    required this.id,
    required this.selfiePhotoUrl,
    required this.signatureUrl,
    required this.createdAt,
    required this.amount,
    required this.additionalCharges,
    required this.updatedAt,
    required this.loanId,
    required this.status,
  });

  @JsonKey(
    name: 'created_at',
    toJson: handleDateTimeToJson,
    fromJson: handleDateTimeFromJson,
  )
  @override
  late DateTime createdAt;

  @JsonKey(
    name: 'deleted_at',
    toJson: handleDateTimeToJson,
    fromJson: handleDateTimeNullableFromJson,
  )
  @override
  DateTime? deletedAt;

  @JsonKey(
    name: 'updated_at',
    toJson: handleDateTimeToJson,
    fromJson: handleDateTimeFromJson,
  )
  @override
  late DateTime updatedAt;

  @override
  late String id;

  @JsonKey(
    name: 'loan_id',
  )
  late String loanId;

  late double amount;

  String? description;

  @JsonKey(
    name: 'additional_charges',
    defaultValue: 0.0,
  )
  late double additionalCharges;

  @JsonKey(
    name: 'advance_charges',
    defaultValue: 0.0,
  )
  late double advanceCharges;

  @JsonKey(
    defaultValue: 0.0,
  )
  late double deductions;

  @JsonKey(
    name: 'signature_url',
    toJson: handleImageUrlToJson,
  )
  late ImageUrl signatureUrl;

  @JsonKey(
    name: 'selfie_photo_url',
    toJson: handleImageUrlToJson,
  )
  late ImageUrl selfiePhotoUrl;

  @JsonKey(
    name: 'uploaded_files_urls',
    toJson: handleFileUrlsToJson,
  )
  late List<FileUrl> uploadedFilesUrls;

  @JsonKey(
    defaultValue: LoanStatus.pending,
  )
  late LoanStatus status;

  Map<String, dynamic> toJson() {
    return _$AdditionalLoanAmountEntityToJson(this);
  }

  @override
  List<Object?> get props => [
        id,
        createdAt,
        updatedAt,
        amount,
        additionalCharges,
        advanceCharges,
        deductions,
        description,
        selfiePhotoUrl,
        signatureUrl,
        uploadedFilesUrls,
        loanId,
        status,
      ];

  @override
  bool? get stringify => true;

  AdditionalLoanAmount toAdditionalLoanAmount() {
    return AdditionalLoanAmount()
      ..createdAt = createdAt
      ..updatedAt = updatedAt
      ..deletedAt = deletedAt
      ..id = id
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
}
