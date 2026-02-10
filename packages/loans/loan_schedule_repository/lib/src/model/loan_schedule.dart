import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/src/model/loan_schedule_entity.dart';
import 'package:loooans_helpers/data_helpers.dart';

class LoanSchedule extends LoanScheduleEntity
    implements BaseModel<LoanScheduleEntity> {
  LoanSchedule() : super();

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
}
