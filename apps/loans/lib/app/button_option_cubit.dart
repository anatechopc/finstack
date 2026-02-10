import 'package:bloc/bloc.dart';
import 'package:loooans/widgets/app_widgets.dart';
import 'package:meta/meta.dart';

part 'button_option_state.dart';

class ButtonOptionCubit extends Cubit<ButtonOption> {
  ButtonOptionCubit({ required ButtonOption initial}) : super(initial);

  void selectOption(ButtonOption option) {
    emit(option);
  }
}
