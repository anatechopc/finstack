import 'package:json_annotation/json_annotation.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:payment_repository/src/model/payment.dart';

part 'payment_entity.g.dart';

@JsonSerializable()
class PaymentEntity implements BaseEntity {
  PaymentEntity();

  PaymentEntity._({
    required this.createdAt,
    required this.updatedAt,
    required this.id,
    required this.userId,
    required this.loanScheduleId,
  });

  factory PaymentEntity.fromJson(Map<String, dynamic> json) {
    return _$PaymentEntityFromJson(json);
  }

  @JsonKey(
    name: 'created_at',
    toJson: handleDateTimeToJson,
    fromJson: handleDateTimeFromJson,
  )
  @override
  late DateTime createdAt;

  @JsonKey(
    name: 'deleted_at',
    toJson: handleDateTimeToJson,
    fromJson: handleDateTimeNullableFromJson,
  )
  @override
  DateTime? deletedAt;

  @JsonKey(
    name: 'updated_at',
    toJson: handleDateTimeToJson,
    fromJson: handleDateTimeFromJson,
  )
  @override
  late DateTime updatedAt;

  @override
  late String id;

  @JsonKey(name: 'user_id')
  late String userId;

  @JsonKey(name: 'loan_schedule_id')
  late String loanScheduleId;

  @JsonKey(
    name: 'transaction_photo_url',
    toJson: handleImageUrlToJson,
  )
  ImageUrl? transactionPhotoUrl;

  @JsonKey(
    name: 'signature_url',
    toJson: handleImageUrlToJson,
  )
  ImageUrl? signatureUrl;

  @JsonKey(name: 'auto_collect_ref')
  String? autoCollectRef;

  @JsonKey(name: 'confirmed_by')
  String? confirmedBy;

  String? comment;

  @JsonKey(
    name: 'confirmed_at',
    toJson: handleDateTimeToJson,
    fromJson: handleDateTimeNullableFromJson,
  )
  DateTime? confirmedAt;

  @override
  List<Object?> get props => [
        createdAt,
        updatedAt,
        deletedAt,
        id,
        userId,
        loanScheduleId,
        transactionPhotoUrl,
        autoCollectRef,
        confirmedBy,
        comment,
        signatureUrl,
        confirmedAt,
      ];

  @override
  bool? get stringify => true;

  Map<String, dynamic> toJson() {
    return _$PaymentEntityToJson(this);
  }

  Payment toPayment() {
    return Payment()
      ..createdAt = createdAt
      ..updatedAt = updatedAt
      ..deletedAt = deletedAt
      ..id = id
      ..userId = userId
      ..loanScheduleId = loanScheduleId
      ..transactionPhotoUrl = transactionPhotoUrl
      ..autoCollectRef = autoCollectRef
      ..confirmedBy = confirmedBy
      ..comment = comment
      ..signatureUrl = signatureUrl
      ..confirmedAt = confirmedAt;
  }
}
