part of 'product_bloc.dart';

final class ProductState extends Equatable {
  const ProductState() : this._();

  const ProductState._({
    this.product,
    this.status = ProductStatus.initial,
    this.isLoading = false,
    this.message,
    this.extraData,
  });

  const ProductState.selected({required Product? product})
      : this._(
          product: product,
          status: ProductStatus.selected,
        );

  const ProductState.loanSelected({required Product? product})
      : this._(
    product: product,
    status: ProductStatus.loanSelected,
  );

  const ProductState.unselected()
      : this._(
          product: null,
          status: ProductStatus.unselected,
        );

  const ProductState.loading({bool isLoading = false})
      : this._(
          isLoading: isLoading,
          status: ProductStatus.loading,
        );

  const ProductState.success({String? message})
      : this._(
          message: message,
          status: ProductStatus.success,
        );

  const ProductState.error(String message)
      : this._(
          message: message,
          status: ProductStatus.error,
        );

  ProductState.refresh(): this._(
    extraData: DateTime.now().millisecondsSinceEpoch,
    status: ProductStatus.refresh,
  );

  // TODO: convert productView to non-null when ui building is done.
  final Product? product;
  final ProductStatus status;
  final bool isLoading;
  final String? message;
  final dynamic extraData;

  @override
  List<Object?> get props => [
        product,
        status,
        isLoading,
        message,
        extraData,
      ];
}
