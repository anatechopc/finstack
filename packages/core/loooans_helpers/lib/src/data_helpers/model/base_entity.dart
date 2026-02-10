import 'package:equatable/equatable.dart';

/// Entities are classed that describes what data
/// looks like from a database or a cache.
///
/// Every entity should implement this class.
abstract class BaseEntity implements Equatable {
  abstract String id;
  late final DateTime createdAt;
  late DateTime updatedAt;
  DateTime? deletedAt;
}
