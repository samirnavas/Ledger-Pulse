import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

void setUpFocusRingTests() {
  M3EFocusInteraction.resetForTest();
  FocusManager.instance.highlightStrategy =
      FocusHighlightStrategy.alwaysTraditional;
}

void tearDownFocusRingTests() {
  M3EFocusInteraction.resetForTest();
  FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
}
