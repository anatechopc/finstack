import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loooans/features/index/screens/index_screen.dart';
import 'package:loooans/utils/constants.dart';
import 'package:loooans/widgets/force_download_app.dart';

class RouteUtils {
  static GoRoute buildNoTransitionRoute({
    required String path,
    List<GoRoute> routes = const [],
    GlobalKey<NavigatorState>? parentNavigatorKey,
  }) {
    return GoRoute(
      path: path,
      parentNavigatorKey: parentNavigatorKey,
      pageBuilder: (context, state) {
        // final pathParams = state.pathParameters;
        Widget? child;
        final location = state.matchedLocation;

        if (location == '/') {
          if (Constants.forceDownloadNativeApp) {
            child = const ForceDownloadAppScreen();
          } else {
            child = const IndexScreen();
          }
        } /*else if (location.contains(Paths.dashboard)) {
          child = const DashboardScreen();
        } else if (location.contains(Paths.users)) {
          if (pathParams.containsKey('id')) {
            child = UserDetailsScreen();
          } else {
            child = UsersScreen();
          }
        } else if (location.contains(Paths.produce)) {
          child = ProduceScreen();
        } else if (location.contains(Paths.orders)) {
          if (pathParams.containsKey('id')) {
            if (!AuthenticationService.instance.isCustomer) {
              child = OrderDetailScreen();
            } else {
              child = ClientOrderDetailScreen();
            }
          } else {
            child = OrdersScreen();
          }
        } else if (location.contains(Paths.deliveries)) {
          if (pathParams.containsKey('id')) {
            child = DeliveryDetailScreen();
          } else {
            child = DeliveriesScreen();
          }
        } else if (location.contains(Paths.checkout)) {
          final action = pathParams['action'];

          if (action != null && action == Paths.actionCustom) {
            child = CustomItemsCheckoutScreen();
          } else {
            child = CheckoutScreen();
          }
        } else if (location.contains(Paths.payment)) {
          child = PaymentScreen();
        } else if (location.contains(Paths.userProfile)) {
          child = ProfileScreen();
        } else if (location.contains(Paths.register)) {
          child = AddUserScreen()..isCustomer = true;
        }*/

        if (child == null) {
          throw Exception('Child in routes must not be null');
        }

        return NoTransitionPage<dynamic>(child: child);
      },
      routes: routes,
    );
  }

  static GoRoute buildDefaultTransitionRoute({
    required String path,
    bool opaque = true,
    List<GoRoute> routes = const [],
    bool fullScreenDialog = false,
    GlobalKey<NavigatorState>? parentNavigatorKey,
  }) {
    return GoRoute(
      path: path,
      parentNavigatorKey: parentNavigatorKey,
      pageBuilder: (context, state) {
        // final pathParams = state.pathParameters;
        // final location = state.matchedLocation;
        // Widget? child;
        // const animateTransition = true;

        // possible Path.users will be in here
        // if (location.contains(Paths.user)) {
        //   final action = pathParams['action'];
        //
        //   if (action == Paths.actionAdd) {
        //     child = AddUserScreen();
        //   } else if (action == Paths.actionUpdate) {
        //     child = AddUserScreen()..isUpdate = true;
        //   }
        // } else if (location.contains(Paths.produce)) {
        //   final action = pathParams['action'];
        //   final extra = state.extra;
        //   var actionIsId = false;
        //   var updateBatch = false;
        //
        //   if (extra != null && extra is Map<String, dynamic>) {
        //     if (extra.containsKey('actionIsId')) {
        //       actionIsId = extra['actionIsId'] as bool;
        //     }
        //
        //     if (extra.containsKey('animateTransition')) {
        //       animateTransition = extra['animateTransition'] as bool;
        //     }
        //
        //     if (extra.containsKey('updateBatch')) {
        //       updateBatch = extra['updateBatch'] as bool;
        //     }
        //   }
        //
        //   if (action == Paths.actionAdd) {
        //     child = AddProduceScreen();
        //   } else if (action == Paths.actionUpdate) {
        //     child = AddProduceScreen()
        //       ..isUpdate = true
        //       ..isUpdateBatch = updateBatch;
        //   } else if (actionIsId) {
        //     child = ProduceDetailScreen();
        //   }
        // } else if (location.contains(Paths.order)) {
        //   if (pathParams.containsKey('action')) {
        //     final action = pathParams['action'];
        //
        //     if (action == Paths.actionConfirm) {
        //       child = ConfirmOrderScreen();
        //     }
        //   }
        // } else if (location.contains(Paths.delivery)) {
        //   if (pathParams.containsKey('action')) {
        //     final action = pathParams['action'];
        //     final extras = state.extra as Map<String, dynamic>?;
        //
        //     if (action == Paths.actionAdd) {
        //       child = DeliverOrderScreen();
        //
        //       if (extras != null && extras.containsKey('orderModel')) {
        //         (child as DeliverOrderScreen).orderModel =
        //             extras['orderModel'] as OrderModel;
        //       }
        //     }
        //   }
        // }

        throw Exception('Child in routes must not be null');
      
        // if (!animateTransition) {
        //   return NoTransitionPage(child: child);
        // }
        //
        // return buildPageWithDefaultTransition<dynamic>(
        //   context: context,
        //   state: state,
        //   child: child,
        //   opaque: opaque,
        //   fullScreenDialog: fullScreenDialog,
        // );
      },
      routes: routes,
    );
  }

  static CustomTransitionPage<T> buildPageWithDefaultTransition<T>({
    required BuildContext context,
    required GoRouterState state,
    required Widget child,
    bool opaque = true,
    bool fullScreenDialog = false,
  }) {
    return CustomTransitionPage<T>(
      key: state.pageKey,
      child: child,
      barrierDismissible: !opaque,
      opaque: opaque,
      fullscreenDialog: fullScreenDialog,
      barrierColor: opaque ? Colors.white : Colors.black.withOpacity(0.6),
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(opacity: animation, child: child),
    );
  }
}
