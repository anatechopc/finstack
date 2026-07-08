import 'package:collection/collection.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/app/routing/route_utils.dart';
import 'package:loooans/app/view/page_not_found.dart';
import 'package:loooans/features/authentication/bloc/authentication_bloc.dart';
import 'package:loooans/features/authentication/screen/email_verification_screen.dart';
import 'package:loooans/features/authentication/screen/login_screen.dart';
import 'package:loooans/features/authentication/screen/mobile_verification_screen.dart';
import 'package:loooans/features/authentication/screen/verification_hub_screen.dart';
import 'package:loooans/features/chat/bloc/chat_bloc.dart';
import 'package:loooans/features/chat/screen/chat_room_screen.dart';
import 'package:loooans/features/chat/screen/conversations_screen.dart';
import 'package:loooans/features/index/screens/home_screen.dart';
import 'package:loooans/features/index/screens/index_screen.dart';
import 'package:loooans/features/loans/screens/loan_details.dart';
import 'package:loooans/features/main/screen/main_screen.dart';
import 'package:loooans/features/payment_center/screen/payment_center_screen.dart';
import 'package:loooans/features/products/bloc/product_bloc.dart';
import 'package:loooans/features/products/screen/add_product_screen.dart';
import 'package:loooans/features/products/screen/loan_application.dart';
import 'package:loooans/features/products/screen/loan_offer_detail.dart';
import 'package:loooans/features/registration/screens/register_screen.dart';
import 'package:loooans/features/registration/screens/registration_complete_screen.dart';
import 'package:loooans/features/reports/bloc/reports_bloc.dart';
import 'package:loooans/features/reports/screen/dashboard_screen.dart';
import 'package:loooans/features/set_password/cubit/set_password_cubit.dart';
import 'package:loooans/features/set_password/screen/set_password_screen.dart';
import 'package:loooans/features/users/screens/loan_client_detail.dart';
import 'package:loooans/features/users/screens/update_profile_screen.dart';
import 'package:loooans/features/users/screens/users_screen.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/services/notification_service.dart';
import 'package:loooans/services/settings_service.dart';
import 'package:user_loan_view_repository/user_loan_view_repository.dart';
import 'package:user_repository/user_repository.dart';

RouterConfig<Object> buildAppRoutes() {
  var servicesInitialized = false;

  return GoRouter(
    errorPageBuilder: (context, state) {
      return RouteUtils.buildPageWithDefaultTransition<dynamic>(
        context: context,
        state: state,
        child: const PageNotFound(),
      );
    },
    redirect: (context, state) async {
      final path = state.uri.path;

      await context.read<AuthenticationBloc>().initializeAuth();
      if (!servicesInitialized) {
        NotificationService.initialize(context);
        SettingsService.initialize();
        servicesInitialized = true;
      }

      try {
        final user = AuthenticationService.instance.user;

        // Public paths and the verify screen itself bypass the verification
        // gate. Without this guard the redirect would loop on the verify
        // screen, and unauthenticated browsing of /, /login etc. would be
        // blocked unnecessarily.
        if (Paths.publicPaths.singleWhereOrNull((p) => p == path) != null) {
          return null;
        }
        if (path == Paths.verify ||
            path == Paths.verifyEmail ||
            path == Paths.mobileVerification) {
          return null;
        }
        // Anonymous placeholder users are pre-login browsers — no gate.
        if (user.isPlaceholder) {
          return null;
        }

        // Gate: require BOTH email and mobile number to be verified before
        // any authenticated route is reachable. Firebase Auth owns email
        // verification; the mobileNumberVerified bit is owned by our backend.
        final firebaseUser = FirebaseAuth.instance.currentUser;
        final emailVerified = firebaseUser?.emailVerified ?? false;
        final mobileVerified = (user.verificationStatus &
                UserVerificationStatus.mobileNumberVerified.value) !=
            0;
        if (!emailVerified || !mobileVerified) {
          return Paths.verify;
        }

        return null;
      } catch (err) {
        if (Paths.publicPaths.singleWhereOrNull((p) => p == path) != null) {
          return null;
        }

        return Paths.index;
      }
    },
    routes: [
      GoRoute(
        path: Paths.register,
        builder: (context, state) {
          final queryParams = state.uri.queryParameters;
          String? registerAs;

          if (queryParams.containsKey('as')) {
            registerAs = queryParams['as'];
          }

          return RegisterScreen(
            registerAs: registerAs,
          );
        },
      ),
      GoRoute(
        path: Paths.registerComplete,
        builder: (context, state) {
          var isInitial = false;
          String? as;

          if (state.uri.queryParameters.containsKey('initial')) {
            isInitial = bool.parse(state.uri.queryParameters['initial']!);
          }

          if (state.uri.queryParameters.containsKey('as')) {
            as = state.uri.queryParameters['as'];
          }

          return RegistrationCompleteScreen(
            isInitial: isInitial,
            isProvider: as == 'provider',
          );
        },
      ),
      GoRoute(
        path: Paths.login,
        builder: (context, state) {
          return LoginScreen();
        },
      ),
      GoRoute(
        path: Paths.setPassword,
        builder: (context, state) {
          final token = state.uri.queryParameters['token'];

          return BlocProvider(
            create: (context) => SetPasswordCubit(context.read<UserRepository>()),
            child: SetPasswordScreen(token: token),
          );
        },
      ),
      GoRoute(
        path: Paths.verify,
        builder: (context, state) => const VerificationHubScreen(),
      ),
      GoRoute(
        path: Paths.verifyEmail,
        builder: (context, state) => const EmailVerificationScreen(),
      ),
      GoRoute(
        path: Paths.mobileVerification,
        builder: (context, state) => const MobileVerificationScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) {
          if (!AuthenticationService.instance.isLoggedIn) {
            return const IndexScreen();
          }

          if (AuthenticationService.instance.user.isPlaceholder &&
              state.uri.query.isEmpty) {
            return const IndexScreen();
          }

          if (!AuthenticationService.instance.user.isPlaceholder ||
              AuthenticationService.instance.hasCompany) {
            context.read<ReportsBloc>().getReportSummary();
          }

          return StreamBuilder(
            stream: SettingsService.instance.listen(),
            builder: (context, snapshot) {
              var useClassicUI = SettingsService.instance.appUseClassicUI;

              if (snapshot.hasData && snapshot.data != null) {
                useClassicUI = snapshot.data!.useClassicUI;
              }

              if (useClassicUI && state.uri.path == Paths.index) {
                if (state.uri.queryParameters.isEmpty) {
                  GoRouter.of(context).go(Paths.dashboard);
                } else {
                  GoRouter.of(context).go(state.uri.toString());
                }
              } else if (!useClassicUI &&
                  state.uri.path == Paths.dashboard) {
                GoRouter.of(context).go(Paths.index);
              }

              return HomeScreen(
                isClassicUI: useClassicUI,
                child: child,
              );
            },
          );
        },
        routes: [
          GoRoute(
            path: Paths.index,
            builder: (context, state) {
              if (!AuthenticationService.instance.isLoggedIn) {
                return const IndexScreen();
              }
              String? sec;
              String? id;

              if (state.uri.queryParameters.containsKey('sec')) {
                sec = state.uri.queryParameters['sec'];
              }

              if (state.uri.queryParameters.containsKey('id')) {
                id = state.uri.queryParameters['id'];
              }

              return MainScreen(
                key: UniqueKey(),
                section: sec,
                id: id,
              );
            },
          ),
          GoRoute(
            path: Paths.dashboard,
            builder: (context, state) {
              return const DashboardClassicScreen();
            },
          ),
          GoRoute(
            path: Paths.users,
            builder: (context, state) {
              return const UsersScreen();
            },
          ),
          GoRoute(
            path: Paths.paymentCenter,
            builder: (context, state) {
              return const PaymentCenterScreen();
            },
          ),
          GoRoute(
            path: Paths.chat,
            builder: (context, state) => const ConversationsScreen(),
          ),
        ],
      ),
      GoRoute(
        path: Paths.offersAction,
        builder: (context, state) {
          final action = state.pathParameters['action'];

          if (action != null) {
            if (Paths.isPathId(action)) {
              return Scaffold(
                body: LoanOfferDetail(
                  fullScreen: true,
                  id: action,
                  productView: context.read<ProductBloc>().tempProductView,
                ),
              );
            } else if (action == Paths.actionCreate) {
              final extras = state.extra as Map<String, dynamic>?;

              return Scaffold(
                body: AddProductScreen(
                  isFullScreen: true,
                  productId: extras?['product_id'] as String?,
                ),
              );
            }
          }

          return const PageNotFound();
        },
      ),
      GoRoute(
        path: Paths.loansAction,
        builder: (context, state) {
          final action = state.pathParameters['action'];

          if (action != null) {
            if (Paths.isPathId(action)) {
              return LoanDetails(
                id: action,
                fullScreen: true,
              );
            }

            if (action == Paths.actionCreate) {
              final extras = state.extra as Map<String, dynamic>?;
              var amount = 0.0;
              var period = 0;

              if (extras != null) {
                amount = extras['amount'] as double;
                period = extras['period'] as int;
              }

              return Scaffold(
                body: LoanApplication(
                  isFullScreen: true,
                  loanAmount: amount,
                  period: period,
                  productView: context.read<ProductBloc>().tempProductView,
                ),
              );
            }
          }

          return const PageNotFound();
        },
      ),
      GoRoute(
        path: Paths.profileAction,
        builder: (context, state) {
          final action = state.pathParameters['action'];

          if (action != null) {
            if (action == Paths.actionUpdate) {
              return Scaffold(
                body: UpdateProfileScreen(
                  isFullScreen: true,
                ),
              );
            }
          }

          return const PageNotFound();
        },
      ),
      GoRoute(
        path: Paths.clientsAction,
        builder: (context, state) {
          final action = state.pathParameters['action'];

          if (action != null) {
            if (Paths.isPathId(action)) {
              final extras = state.extra! as Map<String, dynamic>;

              return LoanClientDetail(
                productId: extras['productId'] as String,
                userId: extras['userId'] as String,
                loanId: extras['loanId'] as String,
                userLoanView: extras['userLoanView'] as UserLoanView?,
              );
            }
          }

          return const PageNotFound();
        },
      ),
      GoRoute(
        path: Paths.chatRoom,
        builder: (context, state) {
          final roomId = state.pathParameters['roomId']!;
          return BlocProvider(
            create: (ctx) => ChatBloc(ctx, roomId: roomId),
            child: ChatRoomScreen(roomId: roomId),
          );
        },
      ),
    ],
  );
}
