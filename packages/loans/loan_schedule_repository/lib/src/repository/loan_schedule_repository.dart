import 'package:loan_schedule_repository/src/data/database/loan_schedule_firestore_service.dart';
import 'package:loan_schedule_repository/src/model/loan_schedule.dart';
import 'package:loooans_helpers/data_helpers.dart';

///
class LoanScheduleRepository implements BaseRepository<LoanSchedule> {
  /// constructor
  LoanScheduleRepository() : _firestoreService = LoanScheduleFirestoreService();

  late final LoanScheduleFirestoreService _firestoreService;

  @override
  Future<LoanSchedule> add({required LoanSchedule data}) async {
    return _firestoreService
        .add(data: data.toEntity())
        .then((value) => value.toLoanSchedule());
  }

  @override
  Future<LoanSchedule> delete({required LoanSchedule data}) async {
    return _firestoreService
        .delete(data: data.toEntity())
        .then((value) => value.toLoanSchedule());
  }

  @override
  Future<LoanSchedule> get({required String id}) async {
    return _firestoreService
        .get(id: id)
        .timeout(
          timeoutDuration,
          onTimeout: () => _firestoreService.get(id: id, isCache: true),
        )
        .then((value) => value.toLoanSchedule());
  }

  @override
  Future<List<LoanSchedule>> load({
    List<QueryStatement>? statements,
    int? limit = defaultDataLimit,
    int? page,
    bool reset = false,
  }) {
    return _firestoreService
        .load(
          statements: statements,
          limit: limit,
          page: page,
          reset: reset,
        )
        .then(
            (value) => value.map((result) => result.toLoanSchedule()).toList(),);
  }

  @override
  Future<LoanSchedule> update({required LoanSchedule data}) async {
    return _firestoreService
        .update(data: data.toEntity())
        .then((value) => value.toLoanSchedule());
  }

  @override
  Stream<List<LoanSchedule>> get dataStream => _firestoreService.dataStream
      .map((value) => value.map((result) => result.toLoanSchedule()).toList());

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

  Future<List<LoanSchedule>> allByLoanId({
    required String loanId,
    bool onlyPaid = true,
  }) {
    return _firestoreService
        .allByLoanId(
          loanId: loanId,
          onlyPaid: onlyPaid,
        )
        .then(
          (value) => value.map((result) => result.toLoanSchedule()).toList(),
        );
  }
}
