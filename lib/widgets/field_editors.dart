import 'package:flutter/material.dart';
import '../models/objectbox_model.dart';

/// Field editor widget factory based on PropertyType.
/// Returns appropriate editor for each supported type.
/// Unsupported types (flex, vectors) return a read-only display.
class FieldEditor extends StatelessWidget {
  final PropertyInfo prop;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;

  const FieldEditor({
    super.key,
    required this.prop,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final pt = prop.type;

    // ID field: read-only
    if (prop.isId) {
      return _ReadOnlyField(label: prop.name, value: value);
    }

    switch (pt) {
      case 1: // bool
        return _BoolFieldEditor(
          label: prop.name,
          value: value as bool? ?? false,
          onChanged: onChanged,
        );
      case 2: // byte
      case 3: // short
      case 4: // char
      case 5: // int
        return _IntFieldEditor(
          label: prop.name,
          value: value as int?,
          bitWidth: pt == 2 ? 8 : (pt == 3 || pt == 4 ? 16 : 32),
          onChanged: onChanged,
        );
      case 6: // long (int64)
        return _IntFieldEditor(
          label: prop.name,
          value: value as int?,
          bitWidth: 64,
          onChanged: onChanged,
        );
      case 7: // float
        return _DoubleFieldEditor(
          label: prop.name,
          value: value as double?,
          onChanged: onChanged,
        );
      case 8: // double
        return _DoubleFieldEditor(
          label: prop.name,
          value: value as double?,
          onChanged: onChanged,
        );
      case 9: // string
        return _StringFieldEditor(
          label: prop.name,
          value: value as String?,
          onChanged: onChanged,
        );
      case 10: // date (ms since epoch)
        return _DateFieldEditor(
          label: prop.name,
          valueMs: value as int?,
          isNano: false,
          onChanged: onChanged,
        );
      case 11: // relation (target ID)
        return _IntFieldEditor(
          label: prop.name,
          value: value as int?,
          bitWidth: 64,
          onChanged: onChanged,
        );
      case 12: // dateNano (ns since epoch)
        return _DateFieldEditor(
          label: prop.name,
          valueMs: value as int?,
          isNano: true,
          onChanged: onChanged,
        );
      case 13: // flex
      default:
        // Read-only for unsupported types
        return _ReadOnlyField(
          label: prop.name,
          value: value,
          hint: pt == 13 ? 'Flex type (read-only)' : 'Type ${prop.displayType} (read-only)',
        );
    }
  }
}

class _ReadOnlyField extends StatelessWidget {
  final String label;
  final dynamic value;
  final String? hint;

  const _ReadOnlyField({required this.label, this.value, this.hint});

  @override
  Widget build(BuildContext context) {
    return _FieldRow(
      label: label,
      child: InputDecorator(
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          hintText: hint,
        ),
        child: Text(
          value?.toString() ?? 'null',
          style: TextStyle(
            fontFamily: 'monospace',
            color: value == null ? Colors.grey : null,
          ),
        ),
      ),
    );
  }
}

class _BoolFieldEditor extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _BoolFieldEditor({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _FieldRow(
      label: label,
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        dense: true,
        contentPadding: EdgeInsets.zero,
      ),
    );
  }
}

class _IntFieldEditor extends StatelessWidget {
  final String label;
  final int? value;
  final int bitWidth;
  final ValueChanged<int?> onChanged;

  const _IntFieldEditor({
    required this.label,
    required this.value,
    required this.bitWidth,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _FieldRow(
      label: label,
      child: TextFormField(
        initialValue: value?.toString() ?? '',
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Enter $bitWidth-bit integer',
          suffixText: '${bitWidth}bit',
        ),
        keyboardType: TextInputType.number,
        onChanged: (v) {
          final parsed = int.tryParse(v);
          onChanged(parsed);
        },
      ),
    );
  }
}

class _DoubleFieldEditor extends StatelessWidget {
  final String label;
  final double? value;
  final ValueChanged<double?> onChanged;

  const _DoubleFieldEditor({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _FieldRow(
      label: label,
      child: TextFormField(
        initialValue: value?.toString() ?? '',
        decoration: const InputDecoration(
          isDense: true,
          hintText: 'Enter decimal number',
        ),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (v) {
          final parsed = double.tryParse(v);
          onChanged(parsed);
        },
      ),
    );
  }
}

class _StringFieldEditor extends StatelessWidget {
  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;

  const _StringFieldEditor({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _FieldRow(
      label: label,
      child: TextFormField(
        initialValue: value ?? '',
        decoration: const InputDecoration(
          isDense: true,
          hintText: 'Enter text',
        ),
        maxLines: 3,
        minLines: 1,
        onChanged: (v) => onChanged(v.isEmpty ? null : v),
      ),
    );
  }
}

class _DateFieldEditor extends StatelessWidget {
  final String label;
  final int? valueMs;
  final bool isNano;
  final ValueChanged<int?> onChanged;

  const _DateFieldEditor({
    required this.label,
    required this.valueMs,
    required this.isNano,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final ms = isNano ? (valueMs ?? 0) ~/ 1000 : (valueMs ?? 0);
    final dt = ms != 0 ? DateTime.fromMillisecondsSinceEpoch(ms) : null;

    return _FieldRow(
      label: label,
      child: Row(
        children: [
          Expanded(
            child: TextFormField(
              initialValue: dt != null
                  ? '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
                      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}'
                  : '',
              decoration: InputDecoration(
                isDense: true,
                hintText: isNano ? 'Date (ns)' : 'Date (ms)',
              ),
              readOnly: true,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.calendar_today, size: 18),
            onPressed: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: dt ?? DateTime.now(),
                firstDate: DateTime.fromMillisecondsSinceEpoch(0),
                lastDate: DateTime(2100),
              );
              if (date != null) {
                final time = await showTimePicker(
                  context: context,
                  initialTime: dt != null
                      ? TimeOfDay.fromDateTime(dt)
                      : TimeOfDay.now(),
                );
                if (time != null) {
                  final newDt = DateTime(
                    date.year,
                    date.month,
                    date.day,
                    time.hour,
                    time.minute,
                  );
                  final newMs = newDt.millisecondsSinceEpoch;
                  onChanged(isNano ? newMs * 1000 : newMs);
                }
              }
            },
            tooltip: 'Pick date & time',
          ),
        ],
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  final String label;
  final Widget child;

  const _FieldRow({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
