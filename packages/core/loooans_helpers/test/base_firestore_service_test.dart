// ignore_for_file: prefer_const_constructors
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loooans_helpers/data_helpers.dart';

class _Entity implements BaseEntity {
  @override
  String id = '';
  @override
  late final DateTime createdAt;
  @override
  late DateTime updatedAt;
  @override
  DateTime? deletedAt;
  @override
  List<Object?> get props => [id];
  @override
  bool? get stringify => true;
}

class _Service extends BaseFirestoreService<_Entity> {
  _Service({super.firestore});
  @override
  String get collectionName => 'things';
  @override
  Future<_Entity> add({required _Entity data}) => throw UnimplementedError();
  @override
  Future<_Entity> update({required _Entity data}) => throw UnimplementedError();
  @override
  Future<_Entity> delete({required _Entity data}) => throw UnimplementedError();
  @override
  Future<_Entity> get({required String id, bool isCache = false}) async => _Entity();
  @override
  Future<List<_Entity>> load({List<QueryStatement>? statements, int? limit = defaultDataLimit, int? page, bool reset = false}) => throw UnimplementedError();
  @override
  void loadNext({List<QueryStatement>? statements, int? limit = defaultDataLimit, int? page, bool reset = false}) {}
}

void main() {
  test('root uses the injected firestore and dev_ prefix by default', () async {
    final fake = FakeFirebaseFirestore();
    final service = _Service(firestore: fake);
    expect(service.collectionPrefix, 'dev_');
    await service.root.doc('a').set({'x': 1});
    final snap = await fake.collection('dev_things').doc('a').get();
    expect(snap.exists, isTrue);
    expect(snap.data()!['x'], 1);
  });
}
