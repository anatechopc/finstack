
import 'package:collection/collection.dart';

typedef PathTemplate = String;
typedef PathAction = String;
typedef PathExtra = String;
typedef QueryParamKey = String;

class Paths {
  static const PathTemplate dashboard = '/dashboard';
  static const PathTemplate index = '/';
  static const PathTemplate login = '/login';
  static const PathTemplate users = '/users';
  static const PathTemplate usersAction = '$users/:action';
  static const PathTemplate pageNotFound = '/404';
  static const PathTemplate scanQr = '/camera/qr';
  static const PathTemplate takePicture = '/camera/capture';
  static const PathTemplate customers = '/customers';
  static const PathTemplate customersAction = '$customers/:action';
  static const PathTemplate companies = '/companies';
  static const PathTemplate companiesAction = '$companies/:action';
  static const PathTemplate profileAction = '/profile/:action';
  static const PathTemplate verify = '/verify';
  static const PathTemplate mobileVerification = '/verify/mobile';
  static const PathTemplate request = '/request/:action';
  static const PathTemplate requestVerify = '/request/verify';
  static const PathTemplate payment = '/payment';
  static const PathTemplate register = '/register';
  static const PathTemplate registerComplete = '/register/complete';
  static const PathTemplate offersAction = '/offers/:action';
  static const PathTemplate loansAction = '/loans/:action';
  static const PathTemplate clientsAction = '/clients/:action';
  static const PathTemplate borrowersAction = '/borrowers/:action';
  static const PathTemplate paymentCenter = '/payment-center';

  static const PathAction actionCreate = 'create';
  static const PathAction actionUpdate = 'update';
  static const PathAction actionConfirm = 'confirm';
  static const PathAction actionCustom = 'custom';
  static const PathAction actionDetail = 'id';

  static bool isPathId (String action) {
    return allActions.singleWhereOrNull((a) => a == action) == null;
  }

  static final List<PathAction> allActions = [
    actionCreate,
    actionUpdate,
    actionConfirm,
    actionCustom,
  ];

  static final List<PathTemplate> publicPaths =[
    index,
    login,
    register,
    registerComplete,
    pageNotFound,
  ];

  static const PathExtra extraAllowUnauthenticated = 'allowUnauthenticated';
  static const QueryParamKey paramMaxLoanable = 'maxLoanable';
  static const QueryParamKey paramMaxPeriod= 'maxPeriod';
}
