import 'package:flutter/widgets.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../../widgets/playground/controls/play_switch.dart';
import '../../../widgets/playground/play_preview_card.dart';
import '../../../widgets/playground/playground_body.dart';

/// Keyboard focus ring demo — Tab through controls; Space/Enter activates.
class FocusRingPlayground extends StatefulWidget {
  /// Creates the focus ring playground.
  const FocusRingPlayground({super.key});

  @override
  State<FocusRingPlayground> createState() => _FocusRingPlaygroundState();
}

class _FocusRingPlaygroundState extends State<FocusRingPlayground> {
  bool _customColor = false;
  bool _checked = true;
  bool _switched = false;
  double _slider = 0.4;
  int _navIndex = 0;
  final TextEditingController _textController = TextEditingController(
    text: 'Focus me',
  );
  final TextEditingController _searchController = TextEditingController();

  static const List<M3EDropdownItem<String>> _dropdownItems =
      <M3EDropdownItem<String>>[
        M3EDropdownItem(label: 'One', value: 'one'),
        M3EDropdownItem(label: 'Two', value: 'two'),
      ];

  @override
  void dispose() {
    _textController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Widget _ordered(double order, Widget child) {
    return FocusTraversalOrder(order: NumericFocusOrder(order), child: child);
  }

  @override
  Widget build(BuildContext context) {
    final M3EThemeData base = M3ETheme.of(context);
    final M3EThemeData themed = _customColor
        ? base.copyWith(
            focusRingTheme: base.focusRingTheme.copyWith(
              color: base.colorScheme.tertiary,
            ),
          )
        : base;

    return M3ETheme(
      data: themed,
      child: PlaygroundBody(
        pinPreviewsByDefault: true,
        previews: <Widget>[
          PlayPreviewCard(
            label: 'Tab order',
            child: FocusTraversalGroup(
              policy: OrderedTraversalPolicy(),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  _ordered(
                    0,
                    M3EButton.filled(
                      onPressed: () {},
                      child: const Text('Button'),
                    ),
                  ),
                  _ordered(
                    1,
                    M3EIconButton(
                      icon: const Icon(M3EIcons.favorite),
                      tooltip: 'Favorite',
                      onPressed: () {},
                    ),
                  ),
                  _ordered(
                    2,
                    M3ESplitButton<String>(
                      label: 'Split',
                      onPressed: () {},
                      items: const <M3ESplitButtonItem<String>>[
                        M3ESplitButtonItem(value: 'a', child: Text('A')),
                        M3ESplitButtonItem(value: 'b', child: Text('B')),
                      ],
                      onSelected: (_) {},
                    ),
                  ),
                  _ordered(
                    3,
                    SizedBox(
                      width: 160,
                      child: M3ECard(
                        onPressed: () {},
                        child: const Text('Card'),
                      ),
                    ),
                  ),
                  _ordered(
                    4,
                    M3ESwitch(
                      value: _switched,
                      onChanged: (bool v) => setState(() => _switched = v),
                    ),
                  ),
                  _ordered(
                    5,
                    M3ECheckbox(
                      value: _checked,
                      onChanged: (bool? v) =>
                          setState(() => _checked = v ?? false),
                    ),
                  ),
                  _ordered(
                    6,
                    M3EChip(
                      label: 'Chip',
                      type: M3EChipType.filter,
                      selected: _checked,
                      onPressed: () => setState(() => _checked = !_checked),
                    ),
                  ),
                  _ordered(
                    7,
                    SizedBox(
                      width: 180,
                      child: M3ESlider(
                        value: _slider,
                        onChanged: (double v) => setState(() => _slider = v),
                      ),
                    ),
                  ),
                  _ordered(
                    8,
                    SizedBox(
                      width: 220,
                      child: M3EDropdownMenu<String>(
                        singleSelect: true,
                        items: _dropdownItems,
                        onSelectionChanged: (_) {},
                      ),
                    ),
                  ),
                  _ordered(
                    9,
                    SizedBox(
                      width: 200,
                      child: M3ETextField(
                        controller: _textController,
                        label: 'Text field',
                      ),
                    ),
                  ),
                  _ordered(
                    10,
                    SizedBox(
                      width: 220,
                      child: M3ESearchBar(
                        controller: _searchController,
                        hintText: 'Search',
                      ),
                    ),
                  ),
                  _ordered(
                    11,
                    M3EFab(onPressed: () {}, icon: const Icon(M3EIcons.add)),
                  ),
                ],
              ),
            ),
          ),
          PlayPreviewCard(
            label: 'Nav bar',
            child: FocusTraversalGroup(
              policy: OrderedTraversalPolicy(),
              child: M3ENavigationBar(
                selectedIndex: _navIndex,
                onDestinationSelected: (int i) => setState(() => _navIndex = i),
                destinations: const <M3ENavigationBarDestination>[
                  M3ENavigationBarDestination(
                    icon: Icon(M3EIcons.home),
                    label: 'Home',
                  ),
                  M3ENavigationBarDestination(
                    icon: Icon(M3EIcons.search),
                    label: 'Search',
                  ),
                  M3ENavigationBarDestination(
                    icon: Icon(M3EIcons.settings),
                    label: 'Settings',
                  ),
                ],
              ),
            ),
          ),
        ],
        controls: <Widget>[
          PlaySwitch(
            label: 'Custom ring color (tertiary)',
            value: _customColor,
            onChanged: (bool v) => setState(() => _customColor = v),
          ),
        ],
        snippets: const <PlaySnippet>[
          PlaySnippet(
            label: 'Override focus ring',
            code: '''
M3ETheme(
  data: theme.copyWith(
    focusRingTheme: const M3EFocusRingTheme(color: Color(0xFF6750A4)),
  ),
  child: child,
)''',
          ),
        ],
      ),
    );
  }
}
