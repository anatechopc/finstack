import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:product_repository/product_repository.dart';
import 'package:user_loan_view_repository/src/model/user_loan_view_entity.dart';
import 'package:user_repository/user_repository.dart';

/// address firestore database service
final class UserLoanViewFirestoreService
    extends BaseFirestoreService<UserLoanViewEntity> {
  UserLoanViewFirestoreService() {
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  }

  @override
  String get collectionName => 'user_loan_views';

  @override
  Future<UserLoanViewEntity> add({required UserLoanViewEntity data}) async {
    final doc = root.doc();
    final updatedData = data..id = doc.id;
    await doc.set(updatedData.toJson());

    return updatedData;
  }

  @override
  Future<UserLoanViewEntity> delete({required UserLoanViewEntity data}) async {
    final updatedData = data..deletedAt = DateTime.timestamp();

    await root.doc(data.id).update(updatedData.toJson());

    return updatedData;
  }

  @override
  Future<UserLoanViewEntity> get({
    required String id,
    bool isCache = false,
  }) async {
    final doc = await root
        .doc(id)
        .get(!isCache ? null : const GetOptions(source: Source.cache));

    return UserLoanViewEntity.fromJson(doc.data()! as Map<String, dynamic>);
  }

  @override
  Future<UserLoanViewEntity> update({required UserLoanViewEntity data}) async {
    final updatedAtNow = DateTime.timestamp();
    data.updatedAt = updatedAtNow;
    await root.doc(data.id).update(data.toJson());

    return data;
  }

  Future<void> updateUserData(User user) async {
    await fs.runTransaction((transaction) async {
      final data = await root
          .where(
            'user_id',
            isEqualTo: user.id,
          )
          .get();
      for (final doc in data.docs) {
        transaction.set(
          doc.reference,
          {
            'user_full_name': user.completeNameWesternOrder,
            'updated_at': DateTime.timestamp().millisecondsSinceEpoch,
          },
        );
      }
    });
  }

  Future<void> updateLoanData(
    Loan loan,
  ) async {
    final data = await root
        .where(
          'loan_id',
          isEqualTo: loan.id,
        )
        .get();
    for (final doc in data.docs) {
      final userLoanViewDoc = root.doc(doc.id);
      await userLoanViewDoc.update(
        {
          'loan_status': loan.status.name,
          'updated_at': DateTime.timestamp().millisecondsSinceEpoch,
        },
      );
    }
  }

  Future<void> updateProductData(Product product) async {
    await fs.runTransaction((transaction) async {
      final data = await root
          .where(
            'product_id',
            isEqualTo: product.id,
          )
          .get();
      for (final doc in data.docs) {
        transaction.set(
          doc.reference,
          {
            'loan_type': product.loanType,
            'updated_at': DateTime.timestamp().millisecondsSinceEpoch,
          },
        );
      }
    });
  }

  @override
  Future<List<UserLoanViewEntity>> load({
    List<QueryStatement>? statements,
    int? limit = defaultDataLimit,
    int? page,
    bool reset = false,
    bool isCache = false,
  }) async {
    if (reset) {
      lastDocumentSnapshot = null;
    }

    var query = root
        .where('deleted_at', isNull: true)
        .orderBy('updated_at', descending: true);

    if (lastDocumentSnapshot != null) {
      query = query.startAfterDocument(lastDocumentSnapshot!);
    }

    if (limit != null && limit > 0) {
      query = query.limit(limit);
    }

    if (statements != null) {
      for (final statement in statements) {
        query = query.where(
          statement.field,
          isEqualTo: statement.isEqualTo,
          arrayContains: statement.arrayContains,
          arrayContainsAny: statement.arrayContainsAny,
          isGreaterThan: statement.isGreaterThan,
          isGreaterThanOrEqualTo: statement.isGreaterThanOrEqualTo,
          isLessThan: statement.isLessThan,
          isLessThanOrEqualTo: statement.isLessThanOrEqualTo,
          isNotEqualTo: statement.isNotEqualTo,
          isNull: statement.isNull,
          whereIn: statement.whereIn,
          whereNotIn: statement.whereNotIn,
        );
      }
    }

    final data = await query
        .get(!isCache ? null : const GetOptions(source: Source.cache));

    if (data.docs.isNotEmpty) {
      lastDocumentSnapshot = data.docs.first;
    }

    return data.docs
        .map(
          (doc) =>
              UserLoanViewEntity.fromJson(doc.data()! as Map<String, dynamic>),
        )
        .toList();
  }

  @override
  Future<void> loadNext({
    List<QueryStatement>? statements,
    int? limit = defaultDataLimit,
    int? page,
    bool reset = false,
  }) async {
    var query = root.where('deleted_at', isNull: true);

    if (limit != null && limit > 0) {
      query = query.limit(limit);
    }

    if (statements != null) {
      for (final statement in statements) {
        query = query.where(
          statement.field,
          isEqualTo: statement.isEqualTo,
          arrayContains: statement.arrayContains,
          arrayContainsAny: statement.arrayContainsAny,
          isGreaterThan: statement.isGreaterThan,
          isGreaterThanOrEqualTo: statement.isGreaterThanOrEqualTo,
          isLessThan: statement.isLessThan,
          isLessThanOrEqualTo: statement.isLessThanOrEqualTo,
          isNotEqualTo: statement.isNotEqualTo,
          isNull: statement.isNull,
          whereIn: statement.whereIn,
          whereNotIn: statement.whereNotIn,
        );
      }
    }

    // the final things
    query = query.orderBy('created_at', descending: true);

    if (!switchStream) {
      final data = await Future.value(query.get()).timeout(
        timeoutDuration,
        onTimeout: () => query.get(const GetOptions(source: Source.cache)),
      );

      final mappedData = data.docs.map(
        (doc) {
          // debugPrint('doc: ${doc.data()}');
          return UserLoanViewEntity.fromJson(
            doc.data()! as Map<String, dynamic>,
          );
        },
      ).toList();

      if (mappedData.length < (limit ?? defaultDataLimit)) {
        switchStream = true;
      }
      // debugPrint('switchStream: $switchStream');

      controller.add(mappedData);

      if (!switchStream) {
        return;
      }
    }

    // debugPrint('stream naaa!');
    // set lastDocumentSnapshot to null to get all data
    // from here on, it is assumed that we have pulled all
    // data from firestore and that it is already cached locally
    lastDocumentSnapshot = null;
    resetStreamController();
    unawaited(
      controller.addStream(
        query.snapshots().map((snapshot) {
          return snapshot.docs
              .map(
                (doc) => UserLoanViewEntity.fromJson(
                    doc.data()! as Map<String, dynamic>,),
              )
              .toList();
        }),
      ),
    );
  }

  @override
  Stream<List<UserLoanViewEntity>> get dataStream => controller.stream;
}
