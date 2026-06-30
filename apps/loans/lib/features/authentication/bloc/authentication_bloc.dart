import 'dart:async';

import 'package:address_repository/address_repository.dart';
import 'package:authentication_repository/authentication_repository.dart';
import 'package:company_repository/company_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans/services/notification_service.dart';
import 'package:loooans/services/session_loader.dart';
import 'package:loooans_helpers/logging_helpers.dart';
import 'package:settings_repository/settings_repository.dart';
import 'package:user_repository/user_repository.dart';

part 'authentication_event.dart';

part 'authentication_state.dart';

class AuthenticationBloc
    extends Bloc<AuthenticationEvent, AuthenticationState> {
  AuthenticationBloc(BuildContext context)
      : authService = AuthenticationService.instance,
        _authenticationRepository = context.read<AuthenticationRepository>(),
        _userRepository = context.read<UserRepository>(),
        _companyRepository = context.read<CompanyRepository>(),
        _addressRepository = context.read<AddressRepository>(),
        _settingsRepository = context.read<SettingsRepository>(),
        super(const AuthenticationState()) {
    on(_handleLoginEvent);
    on(_handleRequestOtpEvent);
    on(_handleVerifyOtpEvent);
    on(_handleSignOutEvent);
    on(_handleForgotPasswordEvent);
  }

  /// Test seam mirroring RegistrationBloc.withDependencies: lets unit tests
  /// inject mocked repositories. Of these, only [userRepository] is exercised
  /// by the forgot-password path. [companyRepository], [addressRepository] and
  /// [settingsRepository] are optional because they are `final` classes (so
  /// they can't be mocked) and are only used by the login/session-loading
  /// handlers, which the forgot-password tests never trigger.
  AuthenticationBloc.withDependencies({
    required AuthenticationRepository authenticationRepository,
    required UserRepository userRepository,
    CompanyRepository? companyRepository,
    AddressRepository? addressRepository,
    SettingsRepository? settingsRepository,
    AuthenticationService? authService,
  })  : authService = authService ?? AuthenticationService.instance,
        _authenticationRepository = authenticationRepository,
        _userRepository = userRepository,
        _companyRepository = companyRepository,
        _addressRepository = addressRepository,
        _settingsRepository = settingsRepository,
        super(const AuthenticationState()) {
    on(_handleLoginEvent);
    on(_handleRequestOtpEvent);
    on(_handleVerifyOtpEvent);
    on(_handleSignOutEvent);
    on(_handleForgotPasswordEvent);
  }

  final log = Logger('authentication_bloc');
  final AuthenticationService authService;
  final AuthenticationRepository _authenticationRepository;
  final UserRepository _userRepository;
  final CompanyRepository? _companyRepository;
  final AddressRepository? _addressRepository;
  final SettingsRepository? _settingsRepository;
  StreamSubscription<Future<String>>? _idTokenChange;
  String? _otpToken;

  @override
  Future<void> close() {
    _idTokenChange?.cancel();
    _idTokenChange = null;
    return super.close();
  }

  void login({
    required String email,
    required String password,
  }) {
    add(LoginEvent(
      email: email,
      password: password,
    ),);
  }

  void requestOtp({String purpose = 'mobile_number'}) {
    add(RequestOtpEvent(purpose: purpose));
  }

  void verifyOtp(String otp) {
    add(VerifyOtpEvent(otp: otp));
  }

  void forgotPassword(String email) => add(ForgotPasswordEvent(email: email));

  void sigOut({
    bool silent = false,
  }) {
    add(
      SignOutEvent(
        silent: silent,
      ),
    );
  }

  void _listenTokenChanges() {
    if (_authenticationRepository.user == null) {
      return;
    }

    _idTokenChange =
        _authenticationRepository.onIdTokenChanges().listen((token) async {
      authService.idToken = await token;
    });
  }

  Future<void> initializeAuth() async {
    try {
      final _ = authService.user;
    } catch (err) {
      final authUser = _authenticationRepository.user;

      if (authUser != null && !authUser.isAnonymous) {
        final user = await _userRepository.get(id: authUser.uid);
        await SessionLoader.loadSession(
          user: user,
          userRepository: _userRepository,
          companyRepository: _companyRepository!,
          addressRepository: _addressRepository!,
          settingsRepository: _settingsRepository!,
        );
      } else {
        await initializeAnonymousUser();
      }
    }
    _listenTokenChanges();
  }

  /// initialize anonymous firebase user to be able to use some functionalities of
  /// the app.
  Future<void> initializeAnonymousUser() {
    authService.user =
        User.createPlaceholder(lastName: 'X', firstName: 'Customer');
    return _authenticationRepository.createAnonymousUser();
  }

  AuthenticationState _checkUserVerificationStatus() {
    final user = authService.user;
    final hasMobileVerified = (user.verificationStatus &
            UserVerificationStatus.mobileNumberVerified.value) !=
        0;
    if (!hasMobileVerified) {
      return const AuthenticationState.verify(
        verifyStatus: UserVerificationStatus.mobileNumberVerified,
      );
    }
    return const AuthenticationState.success(message: 'Successfully logged in');
  }

  Future<void> _handleLoginEvent(
      LoginEvent event, Emitter<AuthenticationState> emit,) async {
    try {
      emit(const AuthenticationState.loading(isLoading: true));
      final authResult = await _authenticationRepository.authenticate(
        email: event.email,
        password: event.password,
      );

      if (authResult.status == AuthenticationStatus.error) {
        throw Exception('Cannot login user');
      }

      final user =
          await _userRepository.get(id: _authenticationRepository.user!.uid);
      await SessionLoader.loadSession(
        user: user,
        userRepository: _userRepository,
        companyRepository: _companyRepository!,
        addressRepository: _addressRepository!,
        settingsRepository: _settingsRepository!,
      );
      _listenTokenChanges();
      NotificationService.instance.startListening(forUser: user.id);

      final finalState = _checkUserVerificationStatus();

      emit(const AuthenticationState.loading());
      // Yield so the BlocListener can fully process the loading-off state
      // before the next emit triggers a route change. On web, without
      // this yield, the route change can race ahead of the listener and
      // leave a dialog stuck on the next screen. See MEMORY.md.
      await Future<void>.delayed(Duration.zero);
      emit(finalState);
    } on AuthenticationException catch (err) {
      log.severe('login error: ${err.message}', err);
      emit(const AuthenticationState.loading());
      emit(AuthenticationState.error(
          message: 'Cannot login user: ${err.message}',),);
    } catch (err) {
      log.severe('login error: $err', err);
      emit(const AuthenticationState.loading());
      emit(AuthenticationState.error(message: 'Login error: $err'));
    }
  }

  Future<void> _handleRequestOtpEvent(
    RequestOtpEvent event,
    Emitter<AuthenticationState> emit,
  ) async {
    try {
      emit(const AuthenticationState.loading(isLoading: true));
      final response = await _userRepository.requestOtp(
        idToken: authService.idToken,
        purpose: event.purpose,
      );
      _otpToken = response.token;
      final canResendAt = DateTime.now().add(const Duration(minutes: 4));
      emit(const AuthenticationState.loading());
      emit(AuthenticationState.requestOtp(
        token: response.token,
        expireAt: response.expireAt,
        canResendAt: canResendAt,
      ),);
    } catch (err) {
      log.severe('Something went wrong: $err', err);
      emit(const AuthenticationState.loading());
      emit(const AuthenticationState.error(message: 'Cannot request OTP'));
    }
  }

  Future<void> _handleVerifyOtpEvent(
    VerifyOtpEvent event,
    Emitter<AuthenticationState> emit,
  ) async {
    try {
      emit(const AuthenticationState.loading(isLoading: true));
      if (_otpToken == null) {
        throw Exception('No active OTP token');
      }
      final verified = await _userRepository.verifyOtp(
        idToken: authService.idToken,
        token: _otpToken!,
        otp: event.otp,
      );
      if (!verified) {
        throw Exception('Invalid OTP');
      }
      // Backend already updated the user doc; refresh into the auth service.
      final updatedUser = await _userRepository.get(id: authService.user.id);
      authService.user = updatedUser;
      // Email verification flips Firebase Auth's emailVerified flag server-side
      // (via Admin SDK in the backend). The local FirebaseUser instance caches
      // the old value — reload() forces a fresh fetch so emailVerified is
      // accurate when the verify screen checks it for smart routing.
      try {
        await _authenticationRepository.user?.reload();
      } catch (_) {
        // Best-effort — reload failure shouldn't block the success flow.
      }
      emit(const AuthenticationState.loading());
      // See _handleLoginEvent for why we yield before a routing emit.
      await Future<void>.delayed(Duration.zero);
      emit(const AuthenticationState.success(message: 'Verify success'));
    } catch (err) {
      log.severe('Verify otp error: $err', err);
      emit(const AuthenticationState.loading());
      emit(AuthenticationState.error(message: 'Cannot verify OTP: $err'));
    }
  }

  Future<void> _handleSignOutEvent(
    SignOutEvent event,
    Emitter<AuthenticationState> emit,
  ) async {
    try {
      if (!event.silent) {
        emit(const AuthenticationState.loading(isLoading: true));
      }
      await _authenticationRepository.signOut();
      _otpToken = null;
      authService.dispose();

      await initializeAnonymousUser();
      if (!event.silent) {
        emit(const AuthenticationState.loading());
        emit(const AuthenticationState.logout());
      }
    } catch (err) {
      log.severe('Logout error: $err', err);
      if (!event.silent) {
        emit(const AuthenticationState.loading());
        emit(AuthenticationState.error(
            message: 'Cannot logout: $err',),);
      }
    }
  }

  Future<void> _handleForgotPasswordEvent(
    ForgotPasswordEvent event,
    Emitter<AuthenticationState> emit,
  ) async {
    try {
      emit(const AuthenticationState.loading(isLoading: true));
      await _userRepository.sendPasswordSetupLink(email: event.email);
      emit(const AuthenticationState.loading());
      emit(const AuthenticationState.success(
        message: 'If an account exists for that email, we sent a reset link.',
      ),);
    } catch (err) {
      log.severe('ForgotPassword error: $err', err);
      emit(const AuthenticationState.loading());
      // Neutral message — never reveal whether the account exists.
      emit(const AuthenticationState.success(
        message: 'If an account exists for that email, we sent a reset link.',
      ),);
    }
  }
}
