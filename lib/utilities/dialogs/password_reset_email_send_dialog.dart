import 'package:flutter/material.dart';
import 'package:app1/utilities/dialogs/generic_dialog.dart';

Future<void> showPasswordResetSentDialog(BuildContext context) {
  return showGenericDialog<void>(
    context: context,
    title: 'Password Reset',
    content: 'Email untuk reset password sudah dikirim, silakan cek email Anda.',
    optionsBuilder: () => {
      'OK': null,
    },
  );
}