import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:payment_repository/src/data/database/payment_firestore_service.dart';
import 'package:payment_repository/src/model/payment.dart';

///
class PaymentRepository implements BaseRepository<Payment> {
  /// constructor
  PaymentRepository() : _firestoreService = PaymentFirestoreService();

  /// On [firestore] (a fake in tests) instead of the app's Firestore.
  @visibleForTesting
  PaymentRepository.withFirestore(FirebaseFirestore firestore)
      : _firestoreService = PaymentFirestoreService(firestore: firestore);

  late final PaymentFirestoreService _firestoreService;

  @override
  Future<Payment> add({required Payment data}) async {
    return _firestoreService
        .add(data: data.toEntity())
        .then((value) => value.toPayment());
  }

  /// Whether payment [id] exists, read inside [transaction].
  Future<bool> existsIn(Transaction transaction, String id) async =>
      await _firestoreService.getIn(transaction, id) != null;

  /// Queues writing [data] at its own id in [transaction].
  void setIn(Transaction transaction, Payment data) =>
      _firestoreService.setIn(transaction, data.id, data.toEntity().toJson());

  /// Writes [data] at its own id (create or overwrite): a retry with the
  /// same id never adds a second payment.
  Future<Payment> set({required Payment data}) async {
    return _firestoreService
        .set(data: data.toEntity())
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
