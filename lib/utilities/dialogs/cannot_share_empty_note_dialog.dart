import 'package:flutter/material.dart';
import 'package:app1/utilities/dialogs/generic_dialog.dart';

Future<void> showCannotShareEmptyNoteDialog(BuildContext context) {
  return showGenericDialog<void>(
    context: context,
    title: 'Sharing',
    content: 'Kamu tidak bisa membagikan catatan kosong.',
    optionsBuilder: () => {
      'OK': null,
    },
  );
}