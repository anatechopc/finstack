part of 'loans_bloc.dart';

sealed class LoansEvent extends Equatable {
  const LoansEvent();
}

final class SelectLoanEvent extends LoansEvent {

  const SelectLoanEvent({required this.id, this.view});
  final String id;
  final UserLoanView? view;

  @override
  List<Object?> get props => [
        id,
        view,
      ];
}

final class AddLoanEvent extends LoansEvent {

  const AddLoanEvent({
    required this.fields,
    required this.term,
    required this.interestRate,
    this.storeLoan = false,
    this.additionalCharges = const [],
    this.deductions = const [],
    this.product,
    this.user,
    this.coMakers = const [],
    this.parentId,
  });
  final Map<String, dynamic> fields;
  final String term;
  final double interestRate;
  final bool storeLoan;
  final List<Charge> additionalCharges;
  final List<Charge> deductions;
  final Product? product;
  final User? user;
  final List<User> coMakers;
  final String? parentId;

  @override
  List<Object?> get props => [
        fields,
        term,
        interestRate,
        storeLoan,
        additionalCharges,
        deductions,
        product,
        user,
        coMakers,
        parentId,
      ];
}

final class AddRequirementEvent extends LoansEvent {

  const AddRequirementEvent({
    required this.requirement,
    required this.data,
  });
  final Requirement requirement;
  final List<SimpleFileData> data;

  @override
  List<Object?> get props => [
        requirement,
        data,
      ];
}

final class RemoveRequirementEvent extends LoansEvent {

  const RemoveRequirementEvent({
    required this.requirementId,
    required this.index,
  });
  final String requirementId;
  final int index;

  @override
  List<Object?> get props => [
        requirementId,
        index,
      ];
}

final class AddReviewEvent extends LoansEvent {

  const AddReviewEvent({
    required this.review,
    required this.rating,
    required this.productView,
  });
  final String review;
  final int rating;
  final ProductView productView;

  @override
  List<Object?> get props => [
        review,
        rating,
        productView,
      ];
}

final class UpdateLoanStatusEvent extends LoansEvent {

  const UpdateLoanStatusEvent({required this.loanStatus, required this.loan});
  final LoanStatus loanStatus;
  final Loan loan;

  @override
  List<Object?> get props => [
        loanStatus,
        loan,
      ];
}

final class GetLoansByUser extends LoansEvent {

  const GetLoansByUser({
    required this.userId,
    this.allStatus = false,
    this.userIsBorrower = false,
  });
  final String userId;
  final bool allStatus;
  final bool userIsBorrower;

  @override
  List<Object?> get props => [
        userId,
        allStatus,
        userIsBorrower,
      ];
}

final class GetPrincipalBorrowersEvent extends LoansEvent {

  const GetPrincipalBorrowersEvent({required this.userId});
  final String userId;

  @override
  List<Object?> get props => [
        userId,
      ];
}

