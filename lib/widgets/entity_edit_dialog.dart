import 'package:flutter/material.dart';
import '../models/objectbox_model.dart';
import 'field_editors.dart';

/// Dialog for editing an entity object's field values.
///
/// Shows all fields with appropriate editors. ID field is read-only.
/// Returns the modified values map if user clicks Save, or null if cancelled.
Future<Map<String, dynamic>?> showEntityEditDialog({
  required BuildContext context,
  required EntityInfo entity,
  required int objectId,
  required Map<String, dynamic> currentValues,
}) {
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (ctx) => _EntityEditDialog(
      entity: entity,
      objectId: objectId,
      currentValues: currentValues,
    ),
  );
}

class _EntityEditDialog extends StatefulWidget {
  final EntityInfo entity;
  final int objectId;
  final Map<String, dynamic> currentValues;

  const _EntityEditDialog({
    required this.entity,
    required this.objectId,
    required this.currentValues,
  });

  @override
  State<_EntityEditDialog> createState() => _EntityEditDialogState();
}

class _EntityEditDialogState extends State<_EntityEditDialog> {
  late Map<String, dynamic> _values;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _values = Map<String, dynamic>.from(widget.currentValues);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayProps = widget.entity.properties.toList();

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.edit, size: 22, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text('Edit - ${widget.entity.name} #${widget.objectId}'),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Read-only ID field
                _ReadOnlyIdField(objectId: widget.objectId),
                const Divider(height: 24),
                // Editable fields
                for (final prop in displayProps)
                  if (!prop.isId)
                    FieldEditor(
                      prop: prop,
                      value: _values[prop.name],
                      onChanged: (val) {
                        setState(() {
                          if (val == null) {
                            _values.remove(prop.name);
                          } else {
                            _values[prop.name] = val;
                          }
                        });
                      },
                    ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _onSave,
          child: const Text('Save'),
        ),
      ],
    );
  }

  void _onSave() {
    // Collect only the changed values
    final changedValues = <String, dynamic>{};
    for (final entry in _values.entries) {
      final original = widget.currentValues[entry.key];
      if (entry.value != original) {
        changedValues[entry.key] = entry.value;
      }
    }

    // Return all values (including unchanged) for the update operation
    // The CRUD service will merge with existing data
    Navigator.of(context).pop(_values);
  }
}

class _ReadOnlyIdField extends StatelessWidget {
  final int objectId;

  const _ReadOnlyIdField({required this.objectId});

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
                'id',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          Expanded(
            child: InputDecorator(
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
              child: Text(
                '$objectId',
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
