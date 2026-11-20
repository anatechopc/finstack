import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/src/model/loan_schedule_entity.dart';
import 'package:loooans_helpers/data_helpers.dart';

class LoanSchedule extends LoanScheduleEntity
    implements BaseModel<LoanScheduleEntity> {
  LoanSchedule() : super();

  /// A row from its stored JSON ([toJson]).
  factory LoanSchedule.fromJson(Map<String, dynamic> json) =>
      LoanScheduleEntity.fromJson(json).toLoanSchedule();

  factory LoanSchedule.create({
    required DateTime dueAt,
    required String loanId,
    required double outstandingBalance,
    required double principalPayment,
    required double interestCharge,
    required double amortization,
    required double interestDayMultiplier,
    required String companyId,
    double extraPayment = 0,
    bool isOpenTerm = false,
    LoanStatus status = LoanStatus.not_paid,
    double advanceInterestPayments = 0,
    bool isPlaceholder = false,
    double principalLoan = 0,
  }) {
    final now = DateTime.timestamp();

    return LoanSchedule()
      ..createdAt = now
      ..updatedAt = now
      ..id = NO_ID
      ..loanId = loanId
      ..outstandingBalance = outstandingBalance
      ..principalPayment = principalPayment
      ..interestPayment = isOpenTerm ? 0 : interestCharge
      ..extraPayment = extraPayment
      ..amortization = amortization
      ..dueAt = dueAt
      ..status = status
      ..isOpenTerm = isOpenTerm
      ..interestCharge = interestCharge
      ..interestDayMultiplier = interestDayMultiplier
      ..companyId = companyId
      ..advanceInterestPayments = advanceInterestPayments
      ..isPlaceholder = isPlaceholder
      ..principalLoan = principalLoan;
  }

  factory LoanSchedule.createAdditionalLoan({
    required String additionalLoanId,
    required DateTime createdAt,
    required String loanId,
    required double outstandingBalance,
    required double principalPayment,
    required double interestCharge,
    required double amortization,
    required double interestDayMultiplier,
    required String companyId,
    double extraPayment = 0,
    bool isOpenTerm = false,
    LoanStatus status = LoanStatus.not_paid,
    double advanceInterestPayments = 0,
    bool isPlaceholder = false,
    double principalLoan = 0,
  }) {
    final now = DateTime.timestamp();

    return LoanSchedule()
      ..createdAt = createdAt
      ..updatedAt = now
      ..id = additionalLoanId
      ..loanId = loanId
      ..outstandingBalance = outstandingBalance
      ..principalPayment = principalPayment
      ..interestPayment = isOpenTerm ? 0 : interestCharge
      ..extraPayment = extraPayment
      ..amortization = amortization
      ..dueAt = createdAt
      ..status = status
      ..isOpenTerm = isOpenTerm
      ..interestCharge = interestCharge
      ..interestDayMultiplier = interestDayMultiplier
      ..companyId = companyId
      ..advanceInterestPayments = advanceInterestPayments
      ..isPlaceholder = isPlaceholder
      ..principalLoan = principalLoan
      .._isAdditionalLoanAmount = true;
  }

  @override
  LoanScheduleEntity toEntity() {
    return this;
  }

  bool _isAdditionalLoanAmount = false;

  bool isPlaceholder = false;

  double principalLoan = 0;

  bool get isAdditionalLoanAmount {
    return _isAdditionalLoanAmount;
  }

  /// The open-term principal release: the in-memory row 0 ([isPlaceholder]),
  /// or that row as approval stores it for app-managed companies, where
  /// `isPlaceholder` is not kept (finstack#138). Stored, it is open term with
  /// the whole principal as its principal, nothing charged or due, and a
  /// balance of 0 with no interest recorded (unconfirmed, or confirmed from a
  /// submission before #138), or a balance of minus that principal (paid by
  /// a teller, who had to enter interest; the balance started at 0). A 0%
  /// loan's bill paid with principal keeps a balance, records interest, or,
  /// overpaid, ends below 0 by less than its principal. Not a bill; never
  /// paid.
  bool get isPrincipalRelease =>
      !isAdditionalLoanAmount &&
      (isPlaceholder ||
          (isOpenTerm &&
              principalPayment > 0 &&
              interestCharge == 0 &&
              amortization == 0 &&
              ((outstandingBalance + principalPayment).abs() < 0.005 ||
                  (outstandingBalance == 0 && interestPayment == 0))));

  /// The date lateness and overdue status count from: [originalDueAt] when
  /// the open-term engine moved an overdue row's [dueAt] to today, otherwise
  /// [dueAt] (finstack#114); on the rest of a short-paid fixed-term bill,
  /// [partPaidAt] when that is later (#152).
  DateTime get lateFrom {
    final from = originalDueAt ?? dueAt;
    final partPaid = partPaidAt;

    return partPaid != null && partPaid.isAfter(from) ? partPaid : from;
  }
}
