import 'dart:math';

import 'package:loan_repository/loan_repository.dart';
import 'package:loan_repository/src/model/loan_entity.dart';
import 'package:loooans_helpers/data_helpers.dart';

class Loan extends LoanEntity implements BaseModel<LoanEntity> {
  Loan() : super();

  factory Loan.create({
    required String userId,
    required String companyId,
    required String productId,
    required double amount,
    required double additionalCharges,
    required double deductions,
    required int period,
    required List<RequirementSubmission> requirements,
    required bool isForceCollect,
    required LoanStatus status,
    required DateTime? dueAt,
    required String reason,
    required double interestRate,
    required String term,
    required double amortization,
    double additionalChargeUpfrontCollection = 0,
    List<String> coMakerUserIds = const [],
    String? parentId,
    List<Penalty> penalties = const [],
    bool allowLatePayments = false,
  }) {
    final now = DateTime.timestamp();

    return Loan()
      ..createdAt = now
      ..updatedAt = now
      ..id = NO_ID
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

  // for nw, term only supports day and month
  String get completeTerm {
    if (period <= 0) {
      if (term.contains(',')) {
        final splitTerm = term.split(',');
        final tempFirstSalaryDay = int.parse(splitTerm[0]);
        final tempSecondSalaryDay = int.parse(splitTerm[1]);
        final firstSalaryDay = min(tempFirstSalaryDay, tempSecondSalaryDay);
        final secondSalaryDay = max(tempFirstSalaryDay, tempSecondSalaryDay);
        const defaultSuperScript = '\u1d57\u02b0';
        final superscript = switch (firstSalaryDay) {
          1 => '\u02e2\u1d57',
          2 => '\u207f\u1d48',
          3 => '\u02b3\u1d48',
          _ => defaultSuperScript
        };

        return '$firstSalaryDay$superscript and $secondSalaryDay$defaultSuperScript of the month';
      }

      return 'month';
    }

    final numTerm = int.parse(term.substring(0, term.length - 1));
    if (term.contains('d')) {
      if (numTerm > 1) {
        return '$numTerm days';
      }

      return 'day';
    }

    if (numTerm > 1) {
      return '$numTerm months';
    }

    return 'month';
  }

  List<AdditionalLoanAmount> additionalLoanAmounts = [];

  @override
  LoanEntity toEntity() {
    return this;
  }
}
