import 'package:loooans_helpers/data_helpers.dart';
import 'package:product_repository/src/model/charge.dart';
import 'package:product_repository/src/model/product_entity.dart';
import 'package:product_repository/src/model/requirement.dart';

class Product extends ProductEntity implements BaseModel<ProductEntity> {
  Product() : super();

  factory Product.create({
    required String providerId,
    required String loanType,
    required String term,
    required double interestRate,
    required double maxLoanableAmount,
    required int maxPeriod,
    List<Charge> additionalCharges = const [],
    List<Charge> deductions = const [],
    List<Requirement> requirements = const [],
    bool forceCollect = false,
    bool allowRequestMaxLoanAmountExtension = false,
    FileUrl? termsConditionUrl,
    int requiredCoMakerCount = 0,
    bool allowAddOns = true,
    List<FileUrl> additionalLoanDocs = const [],
  }) {
    final now = DateTime.timestamp();

    return Product()
      ..createdAt = now
      ..updatedAt = now
      ..id = NO_ID
      ..providerId = providerId
      ..loanType = loanType
      ..term = term
      ..additionalCharges = additionalCharges
      ..deductions = deductions
      ..forceCollect = forceCollect
      ..interestRate = interestRate
      ..maxLoanableAmount = maxLoanableAmount
      ..allowRequestMaxLoanAmountExtension = allowRequestMaxLoanAmountExtension
      ..termsConditionUrl = termsConditionUrl
      ..requirements = requirements
      ..maxPeriod = maxPeriod
      ..requiredCoMakerCount = requiredCoMakerCount
      ..allowAddOns = allowAddOns
      ..additionalLoanDocs = additionalLoanDocs;
  }

  @override
  ProductEntity toEntity() {
    return this;
  }
}
