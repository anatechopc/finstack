import 'package:bloc/bloc.dart';

class CounterCubit extends Cubit<int> {
  CounterCubit({
    int initValue = 0,
    this.minValue = 0,
    void Function(int val)? onChanged,
  }) : super(initValue) {
    if (onChanged != null) {
      stream.listen((data) {
        onChanged(data);
      });
    }
  }

  int minValue;

  void increase() {
    emit(state + 1);
  }

  void decrease() {
    if (state <= minValue) {
      return;
    }

    emit(state - 1);
  }
}
