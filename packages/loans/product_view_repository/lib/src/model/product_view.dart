import 'package:company_repository/company_repository.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:product_repository/product_repository.dart';
import 'package:product_view_repository/src/model/product_view_entity.dart';

class ProductView extends ProductViewEntity
    implements BaseModel<ProductViewEntity> {
  ProductView() : super();

  factory ProductView.create({
    required String companyId,
    required String companyName,
    required String productId,
    required String loanType,
    required String term,
    required double interestRate,
    required double maxLoanableAmount,
    required int maxPeriod,
    required double reviewRatingAvg,
    required int reviewCount,
    required bool allowAddOns,
    String? tagLine,
    ImageUrl? companyProfilePhotoUrl,
  }) {
    final now = DateTime.timestamp();
    return ProductView()
      ..createdAt = now
      ..updatedAt = now
      ..id = NO_ID
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

  factory ProductView.createFromProductAndCompany({
    required Company company,
    required Product product,
  }) {
    final now = DateTime.timestamp();
    return ProductView()
      ..createdAt = now
      ..updatedAt = now
      ..id = NO_ID
      ..companyId = company.id
      ..companyName = company.name
      ..tagLine = company.tagLine
      ..companyProfilePhotoUrl = company.companyProfilePhotoUrl
      ..productId = product.id
      ..loanType = product.loanType
      ..term = product.term
      ..interestRate = product.interestRate
      ..maxLoanableAmount = product.maxLoanableAmount
      ..reviewRatingAvg = company.totalRating / company.reviewCount
      ..reviewCount = company.reviewCount
      ..maxPeriod = product.maxPeriod
      ..allowAddOns = product.allowAddOns;
  }

  // for nw, term only supports day and month
  String get completeTerm {
    final numTerm = int.parse(term.substring(0, term.length - 1));
    if (term.contains('d')) {
      if (numTerm > 1) {
        return '$numTerm days';
      }

      return 'day';
    }

    if (numTerm > 1) {
      return '$numTerm months';
    }

    return 'month';
  }

  String get completeMaxPeriod {
    if (maxPeriod > 1) {
      return '$maxPeriod mos';
    } else if (maxPeriod <= 0) {
      return 'Open term';
    }

    return '1 mo';
  }

  @override
  ProductViewEntity toEntity() {
    return this;
  }
}
