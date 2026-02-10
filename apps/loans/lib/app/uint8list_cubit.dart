import 'dart:typed_data';

import 'package:bloc/bloc.dart';


class Uint8ListCubit extends Cubit<Uint8List?> {
  Uint8ListCubit() : super(null);

  void update(Uint8List newValue) => emit(newValue);
}
