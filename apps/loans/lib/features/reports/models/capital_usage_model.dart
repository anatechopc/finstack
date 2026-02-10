class CapitalUsageModel {

  const CapitalUsageModel({ required this.totalCapital, required this.products });
  final double totalCapital;
  /// map should be a pair of the name of the product
  /// annd the total capital used by the product
  final Map<String, double> products;
}
