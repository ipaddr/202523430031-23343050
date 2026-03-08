import 'package:flutter/material.dart';
import 'package:app1/utilities/dialogs/generic_dialog.dart';

Future<void> showErrorDialog(
  BuildContext context,
  String text,
) {
  return showGenericDialog<void>(
    context: context,
    title: 'terdapat error',
    content: text,
    optionsBuilder: () => {
      'OK': null,
    },
  );
}