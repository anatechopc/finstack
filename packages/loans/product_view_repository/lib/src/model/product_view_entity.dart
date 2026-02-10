import 'package:json_annotation/json_annotation.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:product_view_repository/src/model/product_view.dart';

part 'product_view_entity.g.dart';

@JsonSerializable()
class ProductViewEntity implements BaseEntity {
  ProductViewEntity();

  ProductViewEntity._({
    required this.createdAt,
    required this.updatedAt,
    required this.id,
    required this.companyId,
    required this.companyName,
    required this.productId,
    required this.loanType,
    required this.term,
    required this.interestRate,
    required this.maxLoanableAmount,
    required this.reviewRatingAvg,
    required this.reviewCount,
    required this.maxPeriod,
  });

  factory ProductViewEntity.fromJson(Map<String, dynamic> json) {
    return _$ProductViewEntityFromJson(json);
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

  @JsonKey(name: 'company_id')
  late String companyId;

  @JsonKey(name: 'company_name')
  late String companyName;

  @JsonKey(name: 'tag_line')
  String? tagLine;

  @JsonKey(
    name: 'company_profile_photo_url',
    toJson: handleImageUrlToJson,
  )
  ImageUrl? companyProfilePhotoUrl;

  @JsonKey(name: 'product_id')
  late String productId;

  @JsonKey(name: 'loan_type')
  late String loanType;

  late String term;

  @JsonKey(name: 'interest_rate')
  late double interestRate;

  @JsonKey(name: 'max_loanable_amount')
  late double maxLoanableAmount;

  /// for open term loans, maxPeriod is 0
  @JsonKey(
    name: 'max_period',
    defaultValue: 1,
  )
  late int maxPeriod;

  @JsonKey(name: 'review_rating_avg')
  late double reviewRatingAvg;

  @JsonKey(name: 'review_count')
  late int reviewCount;

  @JsonKey(
    name: 'allow_add_ons',
    defaultValue: true,
  )
  late bool allowAddOns;

  @override
  List<Object?> get props => [
        createdAt,
        updatedAt,
        deletedAt,
        id,
        companyId,
        companyName,
        tagLine,
        companyProfilePhotoUrl,
        productId,
        loanType,
        term,
        interestRate,
        maxLoanableAmount,
        reviewRatingAvg,
        reviewCount,
        maxPeriod,
        allowAddOns = allowAddOns,
      ];

  @override
  bool? get stringify => true;

  Map<String, dynamic> toJson() {
    return _$ProductViewEntityToJson(this);
  }

  ProductView toProductView() {
    return ProductView()
      ..createdAt = createdAt
      ..updatedAt = updatedAt
      ..deletedAt = deletedAt
      ..id = id
      ..companyId = companyId
      ..companyName = companyName
      ..tagLine = tagLine
      ..companyProfilePhotoUrl = companyProfilePhotoUrl
      ..productId = productId
      ..loanType = loanType
      ..term = term
      ..interestRate = interestRate
      ..maxLoanableAmount = maxLoanableAmount
      ..reviewRatingAvg = reviewRatingAvg
      ..reviewCount = reviewCount
      ..maxPeriod = maxPeriod
      ..allowAddOns = allowAddOns;
  }
}
