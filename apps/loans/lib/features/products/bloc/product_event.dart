part of 'product_bloc.dart';

@immutable
sealed class ProductEvent {}

final class GetProductsEvent extends ProductEvent {
  GetProductsEvent({
    this.reset = false,
  });

  final bool reset;
}

final class AddProductEvent extends ProductEvent {

  AddProductEvent({required this.fields});
  final Map<String, dynamic> fields;
}

final class UpdateProductEvent extends ProductEvent {

  UpdateProductEvent({required this.fields});
  final Map<String, dynamic> fields;
}

final class AddChargeEvent extends ProductEvent {

  AddChargeEvent({required this.fields});
  final Map<String, dynamic> fields;
}

final class RemoveChargeEvent extends ProductEvent {

  RemoveChargeEvent({required this.id});
  final String id;
}

final class AddDeductionEvent extends ProductEvent {

  AddDeductionEvent({required this.fields});
  final Map<String, dynamic> fields;
}

final class RemoveDeductionEvent extends ProductEvent {

  RemoveDeductionEvent({required this.id});
  final String id;
}

final class AddRequirementEvent extends ProductEvent {

  AddRequirementEvent({
    required this.name,
  });
  final String name;
}

final class RemoveRequirementEvent extends ProductEvent {

  RemoveRequirementEvent({required this.id});
  final String id;
}

final class UpdateRequirementEvent extends ProductEvent {

  UpdateRequirementEvent({required this.id, required this.quantity});
  final String id;
  final int quantity;
}

final class UpdatePreviewEvent extends ProductEvent {

  UpdatePreviewEvent({required this.fields});
  final Map<String, dynamic> fields;
}

final class SelectProductEvent extends ProductEvent {

  SelectProductEvent({
    required this.productId,
    this.productView,
    this.forLoans = false,
  });
  final String productId;
  final ProductView? productView;
  final bool forLoans;
}
