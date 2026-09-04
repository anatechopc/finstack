import 'package:json_annotation/json_annotation.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/src/model/loan_schedule.dart';
import 'package:loooans_helpers/data_helpers.dart';

part 'loan_schedule_entity.g.dart';

@JsonSerializable()
class LoanScheduleEntity implements BaseEntity {
  LoanScheduleEntity();

  LoanScheduleEntity._({
    required this.createdAt,
    required this.updatedAt,
    required this.id,
    required this.loanId,
    required this.outstandingBalance,
    required this.principalPayment,
    required this.interestPayment,
    required this.amortization,
    required this.dueAt,
    required this.extraPayment,
    required this.status,
    required this.isOpenTerm,
    required this.interestCharge,
    required this.interestDayMultiplier,
    required this.companyId,
  });

  factory LoanScheduleEntity.fromJson(Map<String, dynamic> json) {
    return _$LoanScheduleEntityFromJson(json);
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

  @JsonKey(name: 'loan_id')
  late String loanId;

  @JsonKey(name: 'company_id')
  late String companyId;

  @JsonKey(name: 'outstanding_balance')
  late double outstandingBalance;

  @JsonKey(name: 'principal_payment')
  late double principalPayment;

  @JsonKey(name: 'interest_payment')
  late double interestPayment;

  @JsonKey(
    name: 'advance_interest_payments',
    defaultValue: 0.0,
  )
  late double advanceInterestPayments;

  late double amortization;

  @JsonKey(name: 'extra_payment')
  late double extraPayment;

  @JsonKey(name: 'payment_id')
  String? paymentId;

  @JsonKey(
    name: 'paid_at',
    toJson: handleDateTimeToJson,
    fromJson: handleDateTimeNullableFromJson,
  )
  DateTime? paidAt;

  @JsonKey(
    name: 'due_at',
    toJson: handleDateTimeToJson,
    fromJson: handleDateTimeFromJson,
  )
  late DateTime dueAt;

  late LoanStatus status;

  @JsonKey(
    name: 'is_open_term',
    defaultValue: false,
  )
  late bool isOpenTerm;

  @JsonKey(name: 'interest_charge')
  late double interestCharge;

  /// This is the multiplier of days on which the interest
  /// is added.
  /// The days are taken from the number of days that has
  /// passed since the last payment schedule.
  ///
  /// This is especially needed for open term loans.
  ///
  ///   e.g last payment date is 2024-Nov-02 and next or current
  ///   payment schedule is 2024-Nov-15, a duration of 13 days
  ///   have passed since the last payment thus the multiplier
  ///   will be:
  ///   [interestDayMultiplier] = 13/30
  ///   [interestDayMultiplier] = 0.43
  ///
  ///   If you have a loan of 10,000 and the monthly interest is
  ///   3%, the interest charge will be 300.
  ///
  ///   The collectable interest payment from the borrower for the
  ///   2024-Nov-15 schedule is:
  ///   [interestPayment] = 300 * 0.43
  ///   [interestPayment] = 129
  ///
  /// NOTE:
  ///   * the basis of total number of days in a month where the
  ///   duration lapsed is taken from is 30. Even if certain months
  ///   have 31 or 28 days, the computation is always 30 days in a
  ///   month.
  @JsonKey(
    name: 'interest_day_multiplier',
    defaultValue: 1,
  )
  late double interestDayMultiplier;

  /// When the money was actually received, set at payment confirmation.
  /// Lateness and penalties are measured from this date, not from [paidAt].
  @JsonKey(
    name: 'collected_at',
    toJson: handleDateTimeToJson,
    fromJson: handleDateTimeNullableFromJson,
  )
  DateTime? collectedAt;

  /// Calendar days between [dueAt] and [collectedAt], floored at 0.
  @JsonKey(name: 'days_late', defaultValue: 0)
  int daysLate = 0;

  /// Penalty amount actually charged on this installment. 0 when on time,
  /// when the loan allows late payments, or when waived.
  @JsonKey(defaultValue: 0.0)
  double penalty = 0;

  /// The penalty definitions that applied, copied from the loan at
  /// confirmation. Lines are recomputed from these plus [daysLate].
  @JsonKey(
    defaultValue: [],
    toJson: Penalty.listToJson,
  )
  List<Penalty> penalties = [];

  /// User id of the provider who waived the penalty, if any.
  @JsonKey(name: 'penalty_waived_by')
  String? penaltyWaivedBy;

  @JsonKey(name: 'penalty_waive_reason')
  String? penaltyWaiveReason;

  @override
  List<Object?> get props => [
        createdAt,
        updatedAt,
        deletedAt,
        id,
        loanId,
        outstandingBalance,
        principalPayment,
        interestPayment,
        amortization,
        paymentId,
        paidAt,
        dueAt,
        extraPayment,
        status,
        isOpenTerm,
        interestCharge,
        interestDayMultiplier,
        companyId,
        advanceInterestPayments,
        collectedAt,
        daysLate,
        penalty,
        penalties,
        penaltyWaivedBy,
        penaltyWaiveReason,
      ];

  @override
  bool? get stringify => true;

  Map<String, dynamic> toJson() {
    return _$LoanScheduleEntityToJson(this);
  }

  LoanSchedule toLoanSchedule() {
    return LoanSchedule()
      ..createdAt = createdAt
      ..updatedAt = updatedAt
      ..deletedAt = deletedAt
      ..id = id
      ..loanId = loanId
      ..outstandingBalance = outstandingBalance
      ..principalPayment = principalPayment
      ..interestPayment = interestPayment
      ..amortization = amortization
      ..paymentId = paymentId
      ..paidAt = paidAt
      ..dueAt = dueAt
      ..extraPayment = extraPayment
      ..status = status
      ..isOpenTerm = isOpenTerm
      ..interestCharge = interestCharge
      ..interestDayMultiplier = interestDayMultiplier
      ..companyId = companyId
      ..advanceInterestPayments = advanceInterestPayments
      ..collectedAt = collectedAt
      ..daysLate = daysLate
      ..penalty = penalty
      ..penalties = penalties
      ..penaltyWaivedBy = penaltyWaivedBy
      ..penaltyWaiveReason = penaltyWaiveReason;
  }
}
