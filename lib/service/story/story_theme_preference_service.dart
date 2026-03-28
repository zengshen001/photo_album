import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../models/story_theme_selection.dart';

class StoryThemePreferenceService {
  StoryThemePreferenceService({File Function()? fileFactory})
    : _fileFactory = fileFactory;

  final File Function()? _fileFactory;

  Future<StoryThemeSelection?> loadLatestSelection() async {
    try {
      final file = await _resolveFile();
      if (!await file.exists()) {
        return null;
      }

      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        return null;
      }

      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) {
        return null;
      }

      final selection = StoryThemeSelection.fromJson(json);
      return selection.isValid ? selection : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveLatestSelection(StoryThemeSelection selection) async {
    final file = await _resolveFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(selection.toJson()));
  }

  Future<File> _resolveFile() async {
    final fileFactory = _fileFactory;
    if (fileFactory != null) {
      return fileFactory();
    }

    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/story_theme_selection.json');
  }
}
