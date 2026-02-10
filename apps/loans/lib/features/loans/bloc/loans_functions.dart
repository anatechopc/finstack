part of 'loans_bloc.dart';

final log = Logger('loans_bloc');

final List<LoanSchedule> _clientLoanSchedules = [];

double _monthlyAmortization = 0;

double _totalLoanPayment = 0;

double _totalLoanAmountReceivable = 0;

void _calculateLoan({
  required double amount,
  required int monthsToPay,
  required DateTime date,
  required double interestRate,
  required String term,
  required String companyId,
  List<LoanSchedule> paidSchedules = const [],
}) {
  _clientLoanSchedules.clear();
  final result = LoanCalculationService.calculateFixedTerm(
    amount: amount,
    monthsToPay: monthsToPay,
    date: date,
    interestRate: interestRate,
    term: term,
    companyId: companyId,
    paidSchedules: paidSchedules,
  );
  _clientLoanSchedules.addAll(result.schedules);
  _monthlyAmortization = result.monthlyAmortization;
  _totalLoanPayment = result.totalLoanPayment;
}

void _calculateLoanOpen({
  required double amount,
  required DateTime date,
  required double interestRate,
  required String term,
  required String companyId,
  List<LoanSchedule> paidSchedules = const [],
  bool forSoa = false,
  Loan? loan,
}) {
  _clientLoanSchedules.clear();
  final result = LoanCalculationService.calculateOpenTerm(
    amount: amount,
    date: date,
    interestRate: interestRate,
    term: term,
    companyId: companyId,
    paidSchedules: paidSchedules,
    forSoa: forSoa,
    loan: loan,
  );
  _clientLoanSchedules.addAll(result.schedules);
  _monthlyAmortization = result.monthlyAmortization;
  _totalLoanPayment = result.totalLoanPayment;
}

double calculateLoanAmount(Loan loan) {
  return LoanCalculationService.calculateLoanAmount(loan);
}
