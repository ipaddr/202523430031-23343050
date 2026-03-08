import 'package:app1/utilities/dialogs/generic_dialog.dart';
import 'package:flutter/material.dart';

Future<bool> showLogOutDialog(BuildContext context) {
  return showGenericDialog<bool>(
    context: context,
    title: 'Log Out',         
    content: 'Apakah kamu yakin ingin logout?',
    optionsBuilder: () => {
        'Cancel': false,
        'Logout': true,
    },
  ).then((value) => value ?? false);
}