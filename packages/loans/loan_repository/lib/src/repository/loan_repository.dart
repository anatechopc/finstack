import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_repository/src/data/database/additional_loan_amount_firestore_service.dart';
import 'package:loan_repository/src/data/database/loan_firestore_service.dart';
import 'package:loan_repository/src/data/database/loan_realtime_database_service.dart';
import 'package:loan_repository/src/model/sales.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:user_loan_view_repository/user_loan_view_repository.dart';

///
class LoanRepository implements BaseRepository<Loan> {
  /// constructor
  LoanRepository()
      : _firestoreService = LoanFirestoreService(),
        _realtimeDatabaseService = LoanRealtimeDatabaseService(),
        _additionalLoanAmountFirestoreService =
            AdditionalLoanAmountFirestoreService();

  /// On [firestore] (a fake in tests) instead of the app's Firestore.
  @visibleForTesting
  LoanRepository.withFirestore(FirebaseFirestore firestore)
      : _firestoreService = LoanFirestoreService(firestore: firestore),
        _realtimeDatabaseService = LoanRealtimeDatabaseService(),
        _additionalLoanAmountFirestoreService =
            AdditionalLoanAmountFirestoreService(firestore: firestore);

  late final LoanFirestoreService _firestoreService;
  late final AdditionalLoanAmountFirestoreService
      _additionalLoanAmountFirestoreService;

  late final LoanRealtimeDatabaseService _realtimeDatabaseService;

  bool get switchStream => _firestoreService.switchStream;

  Future<void> setDatabaseBasePath(String companyId) async {
    _realtimeDatabaseService.basePath = 'companies/$companyId/loans';
  }

  Future<void> addLoanProductTypePair({
    required String loanId,
    required String productType,
  }) async {
    return _realtimeDatabaseService.addLoanProductTypePair(
      loanId: loanId,
      productType: productType,
    );
  }

  @override
  Future<Loan> add({required Loan data}) async {
    return _firestoreService.add(data: data.toEntity()).then((value) async {
      final additionalLoanAmounts = await Future.wait(
        data.additionalLoanAmounts
            .map((additionalLoanAmount) => additionalLoanAmount.toEntity())
            .map(
              (item) => _additionalLoanAmountFirestoreService.add(data: item),
            ),
      );
      return value.toLoan()
        ..additionalLoanAmounts = additionalLoanAmounts
            .map((item) => item.toAdditionalLoanAmount())
            .toList();
    });
  }

  @override
  Future<Loan> delete({required Loan data}) async {
    return _firestoreService.delete(data: data.toEntity()).then((value) async {
      final additionalLoanAmounts = await Future.wait(
        data.additionalLoanAmounts
            .map((additionalLoanAmount) => additionalLoanAmount.toEntity())
            .map(
              (item) =>
                  _additionalLoanAmountFirestoreService.delete(data: item),
            ),
      );
      return value.toLoan()
        ..additionalLoanAmounts = additionalLoanAmounts
            .map((item) => item.toAdditionalLoanAmount())
            .toList();
    });
  }

  @override
  Future<Loan> get({required String id}) async {
    return _firestoreService
        .get(id: id)
        .timeout(
          timeoutDuration,
          onTimeout: () => _firestoreService.get(id: id, isCache: true),
        )
        .then((value) async {
      final additionalLoanAmounts = await _getAdditionalLoanAmounts(loanId: id);

      return value.toLoan()..additionalLoanAmounts = additionalLoanAmounts;
    });
  }

  @override
  Future<List<Loan>> load({
    List<QueryStatement>? statements,
    int? limit = defaultDataLimit,
    int? page,
    bool reset = false,
    bool includeAdditionalLoanAmounts = false,
  }) {
    return _firestoreService
        .load(
      statements: statements,
      limit: limit,
      page: page,
      reset: reset,
    )
        .then((value) {
      final loans = value.map((result) => result.toLoan()).toList();
      if (!includeAdditionalLoanAmounts) {
        return loans;
      }

      return Future.wait(
        loans.map((loan) async {
          final additionalLoanAmounts =
              await _getAdditionalLoanAmounts(loanId: loan.id);

          return loan..additionalLoanAmounts = additionalLoanAmounts;
        }),
      );
    });
  }

  /// Writes the loan [data]. Its new top-ups (no id) are added; the top-ups
  /// it already has are written back only with [updateAdditionalLoanAmounts],
  /// for a caller that changes one (approval, decline). A copy loaded before
  /// a top-up was approved would otherwise reset it to pending, and an
  /// unapproved top-up is not billed (review of finstack#149).
  @override
  Future<Loan> update({
    required Loan data,
    bool updateView = false,
    bool updateAdditionalLoanAmounts = false,
  }) async {
    if (updateView) {
      UserLoanViewRepository().updateLoanData(
        loan: data,
      );
    }

    final updatedLoanData =
        await _firestoreService.update(data: data.toEntity());

    final toUpdateAdditionalLoanAmounts = data.additionalLoanAmounts;
    final addedAdditionalLoanData = <AdditionalLoanAmount>[];

    for (final additionalLoanAmount in toUpdateAdditionalLoanAmounts) {
      if (additionalLoanAmount.id == NO_ID) {
        final addedAdditionalLoanAmount = await _additionalLoanAmountFirestoreService.add(
          data: additionalLoanAmount.toEntity(),
        );
        addedAdditionalLoanData.add(addedAdditionalLoanAmount.toAdditionalLoanAmount());
      } else if (!updateAdditionalLoanAmounts) {
        addedAdditionalLoanData.add(additionalLoanAmount);
      } else {
        final updatedAdditionalLoanAmount = await _additionalLoanAmountFirestoreService.update(
          data: additionalLoanAmount.toEntity(),
        );
        addedAdditionalLoanData.add(updatedAdditionalLoanAmount.toAdditionalLoanAmount());
      }
    }


    return updatedLoanData.toLoan()
      ..additionalLoanAmounts = addedAdditionalLoanData
          .map((item) => item.toAdditionalLoanAmount())
          .toList();
  }

  @override
  Stream<List<Loan>> get dataStream => _firestoreService.dataStream
      .map((value) => value.map((result) => result.toLoan()).toList());

  @override
  void loadNext({
    List<QueryStatement>? statements,
    int? limit = defaultDataLimit,
    int? page,
    bool reset = false,
  }) {
    _firestoreService.loadNext(
      statements: statements,
      limit: limit,
      page: page,
      reset: reset,
    );
  }

  Stream<Sales> get salesStream => _realtimeDatabaseService.stream;

  Future<List<AdditionalLoanAmount>> _getAdditionalLoanAmounts({
    required String loanId,
  }) async {
    return _additionalLoanAmountFirestoreService.load(
      reset: true,
      limit: null,
      statements: [
        QueryStatement(field: 'loan_id', isEqualTo: loanId),
        QueryStatement(
          field: 'status',
          whereIn: [
            LoanStatus.pending.name,
            LoanStatus.approved.name,
          ],
        ),
      ],
    ).then(
      (value) => value.map((item) => item.toAdditionalLoanAmount()).toList(),
    );
  }
}
