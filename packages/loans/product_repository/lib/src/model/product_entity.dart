import 'package:json_annotation/json_annotation.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:product_repository/src/model/charge.dart';
import 'package:product_repository/src/model/product.dart';
import 'package:product_repository/src/model/requirement.dart';

part 'product_entity.g.dart';

@JsonSerializable()
class ProductEntity implements BaseEntity {
  ProductEntity();

  ProductEntity._({
    required this.createdAt,
    required this.updatedAt,
    required this.id,
    required this.providerId,
    required this.loanType,
    required this.term,
    required this.additionalCharges,
    required this.deductions,
    required this.forceCollect,
    required this.interestRate,
    required this.maxLoanableAmount,
    required this.allowRequestMaxLoanAmountExtension,
    required this.requirements,
    required this.maxPeriod,
  });

  factory ProductEntity.fromJson(Map<String, dynamic> json) {
    return _$ProductEntityFromJson(json);
  }

  /// Additional documents required for additional loan applications.
  /// These documents are required to be submitted upon each additional loan application.
  @JsonKey(
    name: 'additional_loan_docs',
    toJson: handleFileUrlsToJson,
    defaultValue: [],
  )
  late List<FileUrl> additionalLoanDocs;

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

  @JsonKey(name: 'provider_id')
  late String providerId;

  @JsonKey(name: 'loan_type')
  late String loanType;

  /// NOTE: term is described by the ff:
  ///   d - day
  ///   m -month
  ///   y - year
  ///  e.g: 1d is 1 day, 1m - 1 month
  ///
  /// Currently, we'll support only monthly and bi-monthly
  /// but in the long run, we should support wide range of
  /// payment terms based on description above.
  late String term;

  @JsonKey(
    name: 'additional_charge',
    toJson: ProductEntity._handleChargesToJson,
  )
  late List<Charge> additionalCharges;

  @JsonKey(
    toJson: ProductEntity._handleChargesToJson,
  )
  late List<Charge> deductions;

  @JsonKey(name: 'force_collect')
  late bool forceCollect;

  @JsonKey(name: 'interest_rate')
  late double interestRate;

  @JsonKey(name: 'max_loanable_amount')
  late double maxLoanableAmount;

  /// max_period computed in months
  @JsonKey(
    name: 'max_period',
    defaultValue: 1,
  )
  late int maxPeriod;

  @JsonKey(name: 'allow_request_max_loan_amount_extension')
  late bool allowRequestMaxLoanAmountExtension;

  @JsonKey(
    name: 'terms_condition_url',
    toJson: handleFileUrlToJson,
  )
  FileUrl? termsConditionUrl;

  @JsonKey(
    toJson: ProductEntity._handleRequirementsToJson,
  )
  late List<Requirement> requirements;

  @JsonKey(
    name: 'required_comaker_count',
    defaultValue: 0,
  )
  late int requiredCoMakerCount;

  /// A flag to determine if the product allows add-ons.
  /// Add-ons are additional products or services that can be added to the loan.
  /// These add ons however increases the overall value of the loan.
  /// Please use it with caution.
  ///
  /// By default, this is set to true.
  /// A user can opt to disallow add-ons by setting this to false.
  /// When set to false, the product can be created as an independent product,
  /// CAN be an add-on to other products but it CANNOT have add-ons.
  ///
  /// Examples of products that can be created as independent products are:
  /// - Regular, fixed-term loans
  /// - Insurances
  /// - and more...
  @JsonKey(
    name: 'allow_add_ons',
    defaultValue: true,
  )
  late bool allowAddOns;

  @override
  List<Object?> get props => [
        createdAt,
        updatedAt,
        deletedAt,
        id,
        providerId,
        loanType,
        term,
        additionalCharges,
        deductions,
        forceCollect,
        interestRate,
        maxLoanableAmount,
        allowRequestMaxLoanAmountExtension,
        termsConditionUrl,
        requirements,
        maxPeriod,
        requiredCoMakerCount,
        allowAddOns,
        additionalLoanDocs,
      ];

  @override
  bool? get stringify => true;

  Map<String, dynamic> toJson() {
    return _$ProductEntityToJson(this);
  }

  static List<Map<String, dynamic>> _handleChargesToJson(List<Charge> charges) {
    return charges.map((c) => c.toJson()).toList();
  }

  static List<Map<String, dynamic>> _handleRequirementsToJson(
    List<Requirement> requirements,
  ) {
    return requirements.map((r) => r.toJson()).toList();
  }

  Product toProduct() {
    return Product()
      ..createdAt = createdAt
      ..updatedAt = updatedAt
      ..deletedAt = deletedAt
      ..id = id
      ..providerId = providerId
      ..loanType = loanType
      ..term = term
      ..additionalCharges = additionalCharges
      ..deductions = deductions
      ..forceCollect = forceCollect
      ..interestRate = interestRate
      ..maxLoanableAmount = maxLoanableAmount
      ..allowRequestMaxLoanAmountExtension = allowRequestMaxLoanAmountExtension
      ..termsConditionUrl = termsConditionUrl
      ..requirements = requirements
      ..maxPeriod = maxPeriod
      ..requiredCoMakerCount = requiredCoMakerCount
      ..allowAddOns = allowAddOns
      ..additionalLoanDocs = additionalLoanDocs;
  }
}
