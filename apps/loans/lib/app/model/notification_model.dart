import 'package:company_repository/company_repository.dart';
import 'package:notification_repository/notification_repository.dart';
import 'package:product_repository/product_repository.dart';

final class NotificationModel {

  const NotificationModel({
    required this.notification,
    this.product,
    this.company,
    this.isFirst = false,
  });
  final Notification notification;
  final Product? product;
  final Company? company;
  final bool isFirst;
}
