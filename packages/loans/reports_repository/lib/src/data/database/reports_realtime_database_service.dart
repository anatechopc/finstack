import 'package:flutter/foundation.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:reports_repository/src/model/capital_usage.dart';
import 'package:reports_repository/src/model/product_totals.dart';
import 'package:reports_repository/src/model/report_summary.dart';
import 'package:reports_repository/src/model/sales.dart';
import 'package:reports_repository/src/model/total_summary_item.dart';

class ReportsRealtimeDatabaseService
    extends BaseRealtimeDatabaseService<ReportSummary> {
  @override
  Future<ReportSummary> add({required ReportSummary data}) {
    // TODO: implement add
    throw UnimplementedError();
  }

  @override
  Future<ReportSummary> delete({required ReportSummary data}) {
    // TODO: implement delete
    throw UnimplementedError();
  }

  @override
  Future<ReportSummary> get({required String id}) {
    return dbRef.once().then((event) =>
        ReportSummary.fromJson(event.snapshot.value! as Map<String, dynamic>),);
  }

  @override
  Future<List<ReportSummary>> load(
      {List<QueryStatement>? statements,
      int? limit = defaultDataLimit,
      int? page,
      bool reset = false,}) {
    // TODO: implement load
    throw UnimplementedError();
  }

  @override
  Future<ReportSummary> update({required ReportSummary data}) {
    // TODO: implement update
    throw UnimplementedError();
  }

  Stream<ReportSummary?> get stream =>
      dbRef.child('report_summary').onValue.map((event) {
        final value = event.snapshot.value;
        if (value == null) {
          return null;
        }

        if (value is Map<dynamic, dynamic>) {
          final transformed = value.map((k, v) {
            final key = k as String;

            if (v is Map<dynamic, dynamic>) {
              return MapEntry(
                key,
                v.map((k2, v2) {
                  final key2 = k2 as String;

                  if (v2 is Map<dynamic, dynamic>) {
                    return MapEntry(key2, v2.map((k3, v3) {
                      final key3 = k3 as String;
                      if (v3 is Map<dynamic, dynamic>) {
                        return MapEntry(k3, v3.map((k4, v4) {
                          return MapEntry(k4 as String, v4);
                        }),);
                      }
                      return MapEntry(key3, v3);
                    }),);
                  }

                  return MapEntry(key2, v2);
                }),
              );
            }

            return MapEntry(key, v);
          });

          return ReportSummary.fromJson(transformed);
        }

        throw Exception('oh no!');
      });

  Future<Map<String, ProductTotals>?> getProducts() async {
    return dbRef.child('report_summary/products').once().then((event) {
      final value = event.snapshot.value;

      if (value == null) {
        return null;
      }

      if (value is Map<dynamic, dynamic>) {
        final transformed = value.map((k, v) {
          return MapEntry(
              k as String,
              (v as Map<dynamic, dynamic>).map((k2, v2) {
                return MapEntry(k2 as String, v2);
              }),);
        });

        return transformed.map((k, v) {
          return MapEntry(k, ProductTotals.fromJson(v));
        });
      }

      throw Exception('Oh no!');
    });
  }

  Future<Map<String, TotalSummaryItem?>> getTotalSummary({
    List<String> keys = const [],
    int chunkSize = 10,
  }) async {
    if (keys.isEmpty) {
      return dbRef.child('report_summary/total_summary').once().then((event) {
        final value = event.snapshot.value;

        if (value is Map<dynamic, dynamic>) {
          final transformed = value.map((k, v) {
            return MapEntry(
              k as String,
              (v as Map<dynamic, dynamic>).map((k2, v2) {
                return MapEntry(k2 as String, v2);
              }),
            );
          });

          return transformed.map((k, v) {
            return MapEntry(k, TotalSummaryItem.fromJson(v));
          });
        }

        throw Exception('Oh no!');
      });
    }

    Future<Map<String, TotalSummaryItem?>> executeCommand(List<String> keys) {
      return Future.wait(
        keys.map((key) {
          return dbRef
              .child('report_summary/total_summary/$key')
              .once()
              .then((event) {
            final value = event.snapshot.value;

            if (value == null) {
              return MapEntry(key, null);
            }

            return MapEntry(
              key,
              TotalSummaryItem.fromJson(
                (value as Map<dynamic, dynamic>).map((k, v) {
                  return MapEntry(k as String, v);
                }),
              ),
            );
          });
        }),
      ).then((values) {
        return values.asMap().map((k, v) => v);
      });
    }

    try {
      if (keys.length > chunkSize) {
        final chunkKeys = _chunkKeys(keys, chunkSize: chunkSize);
        final map = <String, TotalSummaryItem?>{};

        for (final chunk in chunkKeys) {
          final chunkResult = await executeCommand(chunk);
          map.addAll(chunkResult);
          await Future.delayed(const Duration(milliseconds: 200), () {
            debugPrint('200 milliseconds done');
          },);
        }

        return map;
      }
    } catch (err) {
      debugPrint('err her: $err');
      rethrow;
    }

    return executeCommand(keys);
  }

  Future<CapitalUsage?> getCapitalUsage() {
    return dbRef.child('report_summary/capital_usage').once().then((event) {
      if (!event.snapshot.exists) {
        throw Exception('Capital usage not found');
      }

      if (event.snapshot.value == null) {
        return null;
      }

      final value = event.snapshot.value! as Map<dynamic, dynamic>;

      final transformed = value.map((k, v) {
        return MapEntry(k as String, v);
      });

      return CapitalUsage.fromJson(transformed);
    });
  }

  Future<Sales?> getSales() {
    return dbRef.child('report_summary/sales').once().then((event) {
      if (!event.snapshot.exists) {
        throw Exception('Sales not found');
      }

      if (event.snapshot.value == null) {
        return null;
      }

      final value = event.snapshot.value! as Map<dynamic, dynamic>;

      final transformed = value.map((k, v) {
        return MapEntry(k as String, v);
      });

      return Sales.fromJson(transformed);
    });
  }

  List<List<String>> _chunkKeys(List<String> ids, {int chunkSize = 10}) {
    final chunks = <List<String>>[];
    for (var i = 0; i < ids.length; i += chunkSize) {
      chunks.add(ids.sublist(
          i, i + chunkSize > ids.length ? ids.length : i + chunkSize,),);
    }
    return chunks;
  }
}
