import 'package:bloc/bloc.dart';

class TrueFalseCubit extends Cubit<bool> {
  TrueFalseCubit({ bool initialValue = false}) : super(initialValue);

  void trigger() => emit(!state);
}
