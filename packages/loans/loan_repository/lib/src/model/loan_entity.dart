import 'package:json_annotation/json_annotation.dart';
import 'package:loan_repository/src/model/loan.dart';
import 'package:loan_repository/src/model/loan_status.dart';
import 'package:loan_repository/src/model/requirement_submission.dart';
import 'package:loooans_helpers/data_helpers.dart';

part 'loan_entity.g.dart';

@JsonSerializable()
class LoanEntity implements BaseEntity {
  LoanEntity();

  LoanEntity._({
    required this.createdAt,
    required this.updatedAt,
    required this.id,
    required this.userId,
    required this.companyId,
    required this.productId,
    required this.amount,
    required this.additionalCharges,
    required this.deductions,
    required this.period,
    required this.requirements,
    required this.isForceCollect,
    required this.status,
    required this.dueAt,
    required this.reason,
    required this.interestRate,
    required this.term,
    required this.amortization,
  });

  factory LoanEntity.fromJson(Map<String, dynamic> json) {
    return _$LoanEntityFromJson(json);
  }

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

  /// userId is the id of the client
  @JsonKey(name: 'user_id')
  late String userId;

  @JsonKey(name: 'company_id')
  late String companyId;

  @JsonKey(name: 'product_id')
  late String productId;

  late double amount;

  @JsonKey(name: 'additional_charges')
  late double additionalCharges;

  late double deductions;

  // stored in months
  late int period;

  @JsonKey(toJson: LoanEntity._handleRequirementSubmissionsToJson)
  late List<RequirementSubmission> requirements;

  /// value depending on the loan product.
  @JsonKey(name: 'is_force_collect')
  late bool isForceCollect;

  late LoanStatus status;

  /// Null due dates mean that this loan is an open term loan
  /// and will only be done once the customer will close the loan
  /// OR "Early Settlement"
  /// Else, the due date of this loan should not be null;
  @JsonKey(
    name: 'due_at',
    toJson: handleDateTimeToJson,
    fromJson: handleDateTimeNullableFromJson,
  )
  late DateTime? dueAt;

  late String reason;

  @JsonKey(name: 'interest_rate')
  late double interestRate;

  /// the payment frequency of the loan. can be monthly(1m)
  /// or every 15 days(15d).
  /// There will be times that the term will change, especially for
  /// open term loans. In open term loans (period == 0) borrower can
  /// pay per salary date.
  ///
  /// NOTE: Always check the term to determine if it's the normal monthly or
  /// daily frequency OR salary dates of the borrower.
  late String term;

  late double amortization;

  @JsonKey(
    name: 'additional_charge_upfront_collection',
    defaultValue: 0.0,
  )
  late double additionalChargeUpfrontCollection;

  @JsonKey(
    name: 'co_maker_user_ids',
    defaultValue: [],
  )
  late List<String> coMakerUserIds;

  @JsonKey(
    name: 'parent_id',
  )
  late String? parentId;

  /// Penalty terms in force for this loan, copied from the product at
  /// creation. Payment confirmation reads these, never the live product.
  @JsonKey(
    defaultValue: [],
    toJson: Penalty.listToJson,
  )
  List<Penalty> penalties = [];

  /// Copied from the product at creation. When true, late payments are
  /// neither tagged paid_late nor penalized.
  @JsonKey(
    name: 'allow_late_payments',
    defaultValue: false,
  )
  bool allowLatePayments = false;

  @override
  List<Object?> get props => [
        createdAt,
        updatedAt,
        deletedAt,
        id,
        userId,
        companyId,
        productId,
        amount,
        additionalCharges,
        deductions,
        period,
        requirements,
        isForceCollect,
        status,
        dueAt,
        reason,
        interestRate,
        term,
        amortization,
        additionalChargeUpfrontCollection,
        coMakerUserIds,
        parentId,
        penalties,
        allowLatePayments,
      ];

  @override
  bool? get stringify => true;

  Map<String, dynamic> toJson() {
    return _$LoanEntityToJson(this);
  }

  Loan toLoan() {
    return Loan()
      ..createdAt = createdAt
      ..updatedAt = updatedAt
      ..deletedAt = deletedAt
      ..id = id
      ..userId = userId
      ..companyId = companyId
      ..productId = productId
      ..amount = amount
      ..additionalCharges = additionalCharges
      ..deductions = deductions
      ..period = period
      ..requirements = requirements
      ..isForceCollect = isForceCollect
      ..status = status
      ..dueAt = dueAt
      ..reason = reason
      ..interestRate = interestRate
      ..term = term
      ..amortization = amortization
      ..additionalChargeUpfrontCollection = additionalChargeUpfrontCollection
      ..coMakerUserIds = coMakerUserIds
      ..parentId = parentId
      ..penalties = penalties
      ..allowLatePayments = allowLatePayments;
  }

  static List<Map<String, dynamic>> _handleRequirementSubmissionsToJson(
      List<RequirementSubmission> requirements,) {
    return requirements.map((r) => r.toJson()).toList();
  }
}
