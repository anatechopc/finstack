import 'package:loooans_helpers/src/data_helpers/database/base_database_service.dart';
import 'package:loooans_helpers/src/data_helpers/model/base_entity.dart';

/// Base class for all cache access
abstract class BaseCacheService<T extends BaseEntity>
    implements BaseDatabaseService<T> {}
