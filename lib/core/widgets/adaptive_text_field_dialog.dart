import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../theme/adaptive_theme.dart';

/// Class wrapper for static convenience invocation.
class AdaptiveTextFieldDialog {
  static Future<String?> show({
    required BuildContext context,
    required String title,
    String? message,
    String? initialValue,
    String? hintText,
    String? labelText,
    String confirmLabel = 'Save',
    String cancelLabel = 'Cancel',
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
    String? prefixText,
    Widget? prefixIcon,
    bool isDestructive = false,
    String? Function(String?)? validator,
    Key? textFieldKey,
    Key? confirmButtonKey,
    bool autofocus = true,
  }) {
    return showAdaptiveTextFieldDialog(
      context: context,
      title: title,
      message: message,
      initialValue: initialValue,
      hintText: hintText,
      labelText: labelText,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      prefixText: prefixText,
      prefixIcon: prefixIcon,
      isDestructive: isDestructive,
      validator: validator,
      textFieldKey: textFieldKey,
      confirmButtonKey: confirmButtonKey,
      autofocus: autofocus,
    );
  }
}

/// Displays a platform-adaptive text-field dialog (Cupertino on iOS/macOS, Material 3 elsewhere).
///
/// Returns the entered string on confirmation, or `null` if cancelled.
Future<String?> showAdaptiveTextFieldDialog({
  required BuildContext context,
  required String title,
  String? message,
  String? initialValue,
  String? hintText,
  String? labelText,
  String confirmLabel = 'Save',
  String cancelLabel = 'Cancel',
  TextInputType? keyboardType,
  TextCapitalization textCapitalization = TextCapitalization.none,
  String? prefixText,
  Widget? prefixIcon,
  bool isDestructive = false,
  String? Function(String?)? validator,
  Key? textFieldKey,
  Key? confirmButtonKey,
  bool autofocus = true,
}) async {
  final isIos = AdaptiveThemeHelper.isIos(context);

  if (isIos) {
    return showCupertinoDialog<String>(
      context: context,
      builder: (ctx) => _CupertinoTextFieldDialogBody(
        title: title,
        message: message,
        initialValue: initialValue,
        placeholder: hintText ?? labelText,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        keyboardType: keyboardType,
        textCapitalization: textCapitalization,
        prefixText: prefixText,
        isDestructive: isDestructive,
        validator: validator,
        textFieldKey: textFieldKey,
        confirmButtonKey: confirmButtonKey,
        autofocus: autofocus,
      ),
    );
  } else {
    return showDialog<String>(
      context: context,
      builder: (ctx) => _MaterialTextFieldDialogBody(
        title: title,
        message: message,
        initialValue: initialValue,
        hintText: hintText,
        labelText: labelText,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        keyboardType: keyboardType,
        textCapitalization: textCapitalization,
        prefixText: prefixText,
        prefixIcon: prefixIcon,
        isDestructive: isDestructive,
        validator: validator,
        textFieldKey: textFieldKey,
        confirmButtonKey: confirmButtonKey,
        autofocus: autofocus,
      ),
    );
  }
}

class _CupertinoTextFieldDialogBody extends StatefulWidget {
  final String title;
  final String? message;
  final String? initialValue;
  final String? placeholder;
  final String confirmLabel;
  final String cancelLabel;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final String? prefixText;
  final bool isDestructive;
  final String? Function(String?)? validator;
  final Key? textFieldKey;
  final Key? confirmButtonKey;
  final bool autofocus;

  const _CupertinoTextFieldDialogBody({
    required this.title,
    this.message,
    this.initialValue,
    this.placeholder,
    required this.confirmLabel,
    required this.cancelLabel,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.prefixText,
    this.isDestructive = false,
    this.validator,
    this.textFieldKey,
    this.confirmButtonKey,
    this.autofocus = true,
  });

  @override
  State<_CupertinoTextFieldDialogBody> createState() =>
      _CupertinoTextFieldDialogBodyState();
}

class _CupertinoTextFieldDialogBodyState
    extends State<_CupertinoTextFieldDialogBody> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (widget.validator != null) {
      final error = widget.validator!(value);
      if (error != null) {
        setState(() => _errorText = error);
        return;
      }
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoAlertDialog(
      title: Text(widget.title),
      content: Padding(
        padding: const EdgeInsets.only(top: 8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.message != null) ...[
              Text(
                widget.message!,
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
            ],
            CupertinoTextField(
              key: widget.textFieldKey,
              controller: _controller,
              autofocus: widget.autofocus,
              keyboardType: widget.keyboardType,
              textCapitalization: widget.textCapitalization,
              placeholder: widget.placeholder,
              prefix: widget.prefixText != null
                  ? Padding(
                      padding: const EdgeInsets.only(left: 8.0),
                      child: Text(
                        widget.prefixText!,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    )
                  : null,
              onSubmitted: (_) => _submit(),
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 6),
              Text(
                _errorText!,
                style: const TextStyle(
                  color: CupertinoColors.destructiveRed,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text(widget.cancelLabel),
        ),
        CupertinoDialogAction(
          key: widget.confirmButtonKey,
          isDestructiveAction: widget.isDestructive,
          isDefaultAction: !widget.isDestructive,
          onPressed: _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

class _MaterialTextFieldDialogBody extends StatefulWidget {
  final String title;
  final String? message;
  final String? initialValue;
  final String? hintText;
  final String? labelText;
  final String confirmLabel;
  final String cancelLabel;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final String? prefixText;
  final Widget? prefixIcon;
  final bool isDestructive;
  final String? Function(String?)? validator;
  final Key? textFieldKey;
  final Key? confirmButtonKey;
  final bool autofocus;

  const _MaterialTextFieldDialogBody({
    required this.title,
    this.message,
    this.initialValue,
    this.hintText,
    this.labelText,
    required this.confirmLabel,
    required this.cancelLabel,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.prefixText,
    this.prefixIcon,
    this.isDestructive = false,
    this.validator,
    this.textFieldKey,
    this.confirmButtonKey,
    this.autofocus = true,
  });

  @override
  State<_MaterialTextFieldDialogBody> createState() =>
      _MaterialTextFieldDialogBodyState();
}

class _MaterialTextFieldDialogBodyState
    extends State<_MaterialTextFieldDialogBody> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (widget.validator != null) {
      final error = widget.validator!(value);
      if (error != null) {
        setState(() => _errorText = error);
        return;
      }
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(
        widget.title,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 19),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.message != null) ...[
              Text(
                widget.message!,
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              key: widget.textFieldKey,
              controller: _controller,
              autofocus: widget.autofocus,
              keyboardType: widget.keyboardType,
              textCapitalization: widget.textCapitalization,
              decoration: InputDecoration(
                labelText: widget.labelText,
                hintText: widget.hintText,
                prefixText: widget.prefixText != null ? '${widget.prefixText} ' : null,
                prefixIcon: widget.prefixIcon,
                errorText: _errorText,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text(widget.cancelLabel),
        ),
        FilledButton(
          key: widget.confirmButtonKey,
          onPressed: _submit,
          style: widget.isDestructive
              ? FilledButton.styleFrom(backgroundColor: theme.colorScheme.error)
              : null,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
