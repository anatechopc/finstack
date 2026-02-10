import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:company_repository/company_repository.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:product_repository/product_repository.dart';
import 'package:product_view_repository/src/model/product_view_entity.dart';

/// address firestore database service
final class ProductViewFirestoreService
    extends BaseFirestoreService<ProductViewEntity> {
  ProductViewFirestoreService() {
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  }
  @override
  String get collectionName => 'product_views';

  @override
  Future<ProductViewEntity> add({required ProductViewEntity data}) async {
    final doc = root.doc();
    final updatedData = data..id = doc.id;
    await doc.set(updatedData.toJson());

    return updatedData;
  }

  @override
  Future<ProductViewEntity> delete({required ProductViewEntity data}) async {
    final updatedData = data..deletedAt = DateTime.timestamp();

    await root.doc(data.id).update(updatedData.toJson());

    return updatedData;
  }

  @override
  Future<ProductViewEntity> get({
    required String id,
    bool isCache = false,
  }) async {
    final doc = await root
        .doc(id)
        .get(!isCache ? null : const GetOptions(source: Source.cache));

    return ProductViewEntity.fromJson(doc.data()! as Map<String, dynamic>);
  }

  @override
  Future<ProductViewEntity> update({required ProductViewEntity data}) async {
    final updatedAtNow = DateTime.timestamp();
    data.updatedAt = updatedAtNow;
    await root.doc(data.id).update(data.toJson());

    return data;
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
            'term': product.term,
            'interest_rate': product.interestRate,
            'max_loanable_amount': product.maxLoanableAmount,
            'updated_at': DateTime.timestamp().millisecondsSinceEpoch,
          },
        );
      }
    });
  }

  Future<void> updateCompanyData(Company company) async {
    await fs.runTransaction((transaction) async {
      final data = await root
          .where(
            'company_id',
            isEqualTo: company.id,
          )
          .get();
      for (final doc in data.docs) {
        transaction.set(
          doc.reference,
          {
            'company_name': company.name,
            'tag_line': company.tagLine,
            'company_profile_photo_url': company.companyProfilePhotoUrl,
            'review_rating_avg': company.totalRating / company.reviewCount,
            'review_count': company.reviewCount,
            'updated_at': DateTime.timestamp().millisecondsSinceEpoch,
          },
        );
      }
    });
  }

  @override
  Future<List<ProductViewEntity>> load({
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
              ProductViewEntity.fromJson(doc.data()! as Map<String, dynamic>),
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
    query = query.orderBy('created_at');

    if (!switchStream) {
      final data = await Future.value(query.get()).timeout(
        timeoutDuration,
        onTimeout: () => query.get(const GetOptions(source: Source.cache)),
      );

      final mappedData = data.docs
          .map(
            (doc) =>
                ProductViewEntity.fromJson(doc.data()! as Map<String, dynamic>),
          )
          .toList();

      if (mappedData.length < (limit ?? defaultDataLimit)) {
        switchStream = true;
      }
      // debugPrint('switchStream: $switchStream');

      try {
        controller.add(mappedData);
      } catch (err) {}
      // debugPrint('mappedDAta: $mappedData');

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
        query
            .snapshots()
            .map((snapshot) {
          return snapshot.docs
              .map(
                (doc) {
                  // debugPrint('doc: ${doc.data()}');
                  return ProductViewEntity.fromJson(
                      doc.data()! as Map<String, dynamic>,);
                },
              )
              .toList();
        }),
      ),
    );
  }

  @override
  Stream<List<ProductViewEntity>> get dataStream => controller.stream;
}
