import 'package:loooans_helpers/data_helpers.dart';
import 'package:payment_repository/src/data/database/payment_firestore_service.dart';
import 'package:payment_repository/src/model/payment.dart';

///
class PaymentRepository implements BaseRepository<Payment> {
  /// constructor
  PaymentRepository() : _firestoreService = PaymentFirestoreService();

  late final PaymentFirestoreService _firestoreService;

  @override
  Future<Payment> add({required Payment data}) async {
    return _firestoreService
        .add(data: data.toEntity())
        .then((value) => value.toPayment());
  }

  @override
  Future<Payment> delete({required Payment data}) async {
    return _firestoreService
        .delete(data: data.toEntity())
        .then((value) => value.toPayment());
  }

  @override
  Future<Payment> get({required String id}) async {
    return _firestoreService
        .get(id: id)
        .timeout(
          timeoutDuration,
          onTimeout: () => _firestoreService.get(id: id, isCache: true),
        )
        .then((value) => value.toPayment());
  }

  @override
  Future<List<Payment>> load({
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
        .then((value) => value.map((result) => result.toPayment()).toList());
  }

  @override
  Future<Payment> update({required Payment data}) async {
    return _firestoreService
        .update(data: data.toEntity())
        .then((value) => value.toPayment());
  }

  @override
  Stream<List<Payment>> get dataStream => _firestoreService.dataStream
      .map((value) => value.map((result) => result.toPayment()).toList());

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
}
