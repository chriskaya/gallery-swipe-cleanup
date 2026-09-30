/// One colour, icon and label per verdict, shared by the overlay stamp, the
/// tint and the action buttons so the three always agree.
library;

import 'package:flutter/material.dart';

import '../../state/settings.dart';
import '../l10n.dart';

const Color kKeepColor = Color(0xFF22C55E);
const Color kDeleteColor = Color(0xFFEF4444);

extension VerdictStyle on Verdict {
  Color get color => switch (this) {
    Verdict.keep => kKeepColor,
    Verdict.delete => kDeleteColor,
  };

  IconData get icon => switch (this) {
    Verdict.keep => Icons.favorite_rounded,
    Verdict.delete => Icons.delete_rounded,
  };

  String stamp(BuildContext context) => switch (this) {
    Verdict.keep => context.l10n.stampKeep,
    Verdict.delete => context.l10n.stampDelete,
  };

  String action(BuildContext context) => switch (this) {
    Verdict.keep => context.l10n.actionKeep,
    Verdict.delete => context.l10n.actionDelete,
  };
}
