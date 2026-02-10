import 'package:capital_repository/src/model/capital_entity.dart';
import 'package:loooans_helpers/data_helpers.dart';

class Capital extends CapitalEntity implements BaseModel<CapitalEntity> {
  Capital() : super();

  factory Capital.create({
    required String providerId,
    required double amount,
  }) {
    final now = DateTime.timestamp();
    return Capital()
      ..id = NO_ID
      ..createdAt = now
      ..updatedAt = now
      ..providerId = providerId
      ..amount = amount;
  }

  @override
  CapitalEntity toEntity() {
    return this;
  }
}
