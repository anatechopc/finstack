import 'package:equatable/equatable.dart';
import 'package:loooans_helpers/data_helpers.dart';

/// Models are classes that describes what
/// data should we present to the UI.
///
/// Every model should implement this class.
abstract class BaseModel<T extends BaseEntity> implements BaseEntity, Equatable {
  T toEntity();
}
