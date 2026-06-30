import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loooans/features/authentication/bloc/authentication_bloc.dart';
import 'package:loooans/features/set_password/cubit/set_password_cubit.dart';
import 'package:loooans/features/set_password/screen/set_password_screen.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/helpers.dart';

class _MockSetPasswordCubit
    extends MockCubit<SetPasswordState>
    implements SetPasswordCubit {}

class _MockAuthenticationBloc
    extends MockBloc<AuthenticationEvent, AuthenticationState>
    implements AuthenticationBloc {}

void main() {
  late SetPasswordCubit cubit;
  late AuthenticationBloc authBloc;

  setUp(() {
    cubit = _MockSetPasswordCubit();
    authBloc = _MockAuthenticationBloc();
    // The screen has a top-level BlocBuilder<AuthenticationBloc>; keep it in a
    // neutral state so the password card / loading overlay logic is stable.
    when(() => authBloc.state).thenReturn(const AuthenticationState());
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    required String? token,
    required SetPasswordState state,
  }) async {
    when(() => cubit.state).thenReturn(state);

    await tester.pumpApp(
      MultiBlocProvider(
        providers: [
          BlocProvider<SetPasswordCubit>.value(value: cubit),
          BlocProvider<AuthenticationBloc>.value(value: authBloc),
        ],
        child: SetPasswordScreen(token: token),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'shows the invalid-link card when the token is null',
    (tester) async {
      // No token -> the screen short-circuits to the invalid card before it
      // even reads the cubit, so any state works here.
      await pumpScreen(
        tester,
        token: null,
        state: const SetPasswordState(),
      );

      expect(find.text('Link expired or invalid'), findsOneWidget);
      expect(find.textContaining("This link isn't valid"), findsOneWidget);
      expect(find.text('Go to sign in'), findsOneWidget);
      // The password form must NOT be shown.
      expect(find.text('Set password & continue'), findsNothing);
    },
  );

  testWidgets(
    'shows the invalid-link card when the token is empty',
    (tester) async {
      await pumpScreen(
        tester,
        token: '',
        state: const SetPasswordState(),
      );

      expect(find.text('Link expired or invalid'), findsOneWidget);
      expect(find.text('Set password & continue'), findsNothing);
    },
  );

  testWidgets(
    'shows the password form in the default (ready) state',
    (tester) async {
      await pumpScreen(
        tester,
        token: 'token-123',
        state: const SetPasswordState(),
      );

      expect(find.text('Set your password'), findsOneWidget);
      expect(find.text('Set password & continue'), findsOneWidget);

      // The submit button is enabled (tappable) in the ready state.
      final button = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Set password & continue'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(button.onPressed, isNotNull);
    },
  );

  testWidgets(
    'disables the submit button and shows a spinner while submitting',
    (tester) async {
      await pumpScreen(
        tester,
        token: 'token-123',
        state: const SetPasswordState.submitting(),
      );

      // The label is replaced by a spinner while submitting.
      expect(find.text('Set password & continue'), findsNothing);

      // The spinner lives inside the submit button; use it to locate the
      // submit FilledButton specifically (the card has other buttons).
      final submitButtonFinder = find.ancestor(
        of: find.byType(CircularProgressIndicator),
        matching: find.byType(FilledButton),
      );
      expect(submitButtonFinder, findsOneWidget);

      final button = tester.widget<FilledButton>(submitButtonFinder);
      expect(button.onPressed, isNull);
    },
  );
}
