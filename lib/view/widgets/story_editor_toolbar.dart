import 'package:flutter/material.dart';

import 'primary_button.dart';

class StoryEditorToolbar extends StatelessWidget {
  const StoryEditorToolbar({
    super.key,
    required this.canUndo,
    required this.canRedo,
    required this.isSaving,
    required this.hasUnsavedChanges,
    required this.onUndo,
    required this.onRedo,
    required this.onSave,
  });

  final bool canUndo;
  final bool canRedo;
  final bool isSaving;
  final bool hasUnsavedChanges;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final Future<void> Function()? onSave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      elevation: 0,
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.black12),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: canUndo ? onUndo : null,
                    icon: const Icon(Icons.undo),
                    tooltip: '撤销',
                  ),
                  IconButton(
                    onPressed: canRedo ? onRedo : null,
                    icon: const Icon(Icons.redo),
                    tooltip: '重做',
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      hasUnsavedChanges ? '草稿未保存' : '草稿已同步',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: hasUnsavedChanges
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 132,
                    child: PrimaryButton(
                      text: isSaving ? '保存中' : '保存草稿',
                      icon: isSaving ? null : Icons.save_outlined,
                      onPressed: isSaving ? null : onSave,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
