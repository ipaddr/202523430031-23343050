import 'package:app1/utilities/dialogs/generic_dialog.dart';
import 'package:flutter/material.dart';

Future<bool> showDeleteDialog(BuildContext context) {
  return showGenericDialog<bool>(
    context: context,
    title: 'Delete',         
    content: 'Apakah kamu yakin ingin hapus item ini?',
    optionsBuilder: () => {
        'Cancel': false,
        'Yes': true,
    },
  ).then((value) => value ?? false);
}