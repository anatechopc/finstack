import 'package:loan_repository/src/model/sales.dart';
import 'package:loooans_helpers/data_helpers.dart';

class LoanRealtimeDatabaseService extends BaseRealtimeDatabaseService<Sales> {
  Future<void> addLoanProductTypePair({
    required String loanId,
    required String productType,
  }) async {
    return dbRef.child('$loanId:product_type').set(productType);
  }

  @override
  Future<Sales> add({required Sales data}) {
    // TODO: implement add
    throw UnimplementedError();
  }

  @override
  Future<Sales> delete({required Sales data}) {
    // TODO: implement delete
    throw UnimplementedError();
  }

  @override
  Future<Sales> get({required String id}) {
    // TODO: implement get
    throw UnimplementedError();
  }

  @override
  Future<List<Sales>> load(
      {List<QueryStatement>? statements,
      int? limit = defaultDataLimit,
      int? page,
      bool reset = false,}) {
    // TODO: implement load
    throw UnimplementedError();
  }

  @override
  Future<Sales> update({required Sales data}) {
    // TODO: implement update
    throw UnimplementedError();
  }

  Stream<Sales> get stream => dbRef.onValue.map((val) {
        final dddd = val.snapshot.value! as Map<Object?, Object?>;
        return Sales.fromJson(dddd.map((k, v) {
          var updatedValue = v;

          if (v is Map<Object?, Object?>) {
            updatedValue = v.map((k2, v2) {
              var uv2 = v2;

              if (v2 is Map<Object?, Object?>) {
                uv2 = v2.map((k3, v3) {
                  var uv3 = v3;

                  if (v3 is Map<Object?, Object?>) {
                    uv3 = v3.map((k4, v4) {
                      var uv4 = v4;

                      if (v4 is Map<Object?, Object?>) {
                        uv4 = v4.map((k5, v5) {
                          var uv5 = v5;

                          if (v5 is Map<Object?, Object?>) {
                            uv5 = v5.map((k6, v6) {
                              return MapEntry(k6.toString(), v6);
                            });
                          }

                          return MapEntry(k5.toString(), uv5);
                        });
                      }

                      return MapEntry(k4.toString(), uv4);
                    });
                  }

                  return MapEntry(k3.toString(), uv3);
                });
              }

              return MapEntry(k2.toString(), uv2);
            });
          }

          return MapEntry(k.toString(), updatedValue);
        }),);
      });
}
