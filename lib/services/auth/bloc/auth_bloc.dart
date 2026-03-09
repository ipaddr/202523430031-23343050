import 'package:bloc/bloc.dart';
import 'package:app1/services/auth/bloc/auth_state.dart';
import 'package:app1/services/auth/bloc/auth_event.dart';
import 'package:app1/services/auth/auth_provider.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc(AuthProvider provider)
      : super(const AuthStateUninitialized(isLoading: true)) {
//    on<AuthEventShouldRegister>((event, emit) {
//       emit(const AuthStateRegistering(
//         exception: null,
//         isLoading: false,
//       ));
//     });

//     //forgot password
//     on<AuthEventForgotPassword>((event, emit) async {
//       emit(const AuthStateForgotPassword(
//         exception: null,
//         hasSentEmail: false,
//         isLoading: false,
//       ));
//       final email = event.email;
//       if (email == null) {
//         return; // user just wants to go to forgot-password screen
//       }

//       // user wants to actually send a forgot-password email
//       emit(const AuthStateForgotPassword(
//         exception: null,
//         hasSentEmail: false,
//         isLoading: true,
//       ));

//       bool didSendEmail;
//       Exception? exception;
//       try {
//         await provider.sendPasswordReset(toEmail: email);
//         didSendEmail = true;
//         exception = null;
//       } on Exception catch (e) {
//         didSendEmail = false;
//         exception = e;
//       }

//       emit(AuthStateForgotPassword(
//         exception: exception,
//         hasSentEmail: didSendEmail,
//         isLoading: false,
//       ));
//     });
//     // send email verification
//     on<AuthEventSendEmailVerification>((event, emit) async {
//       await provider.sendEmailVerification();
//       emit(state);
//     });
//     on<AuthEventRegister>((event, emit) async {
//       final email = event.email;
//       final password = event.password;
//       try {
//         await provider.createUser(
//           email: email,
//           password: password,
//         );
//         await provider.sendEmailVerification();
//         emit(const AuthStateNeedsVerification(isLoading: false));
//       } on Exception catch (e) {
//         emit(AuthStateRegistering(
//           exception: e,
//           isLoading: false,
//         ));
//       }
//     });
    // initialize
    on<AuthEventInitialize>((event, emit) async {
      await provider.initialize();
      final user = provider.currentUser;
      if (user == null) {
        emit(
          const AuthStateLoggedOut(),
        );
      } else if (!user.isEmailVerified) {
        emit(const AuthStateNeedsVerification());
      } else {
        emit(AuthStateLoggedIn(user));
      }
    });
    
    // log in
    on<AuthEventLogIn>((event, emit) async {
      emit(
        const AuthStateLoggedOut(),
      );
      final email = event.email;
      final password = event.password;
      try {
        final user = await provider.logIn(
          email: email,
          password: password,
        );
        emit(AuthStateLoggedIn(user));          
      } on Exception catch (e) {
        emit(
          AuthStateLoginFailure(e));
      }
    });

    // log out
    on<AuthEventLogOut>((event, emit) async {
      try {
        emit(
          const AuthStateLoading());
          await provider.logOut();
          emit(
            const AuthStateLoggedOut(),
          );
      } on Exception catch (e) {
        emit(AuthStateLogoutFailure(e));
      }
    });

  }
}