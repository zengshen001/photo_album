import 'package:flutter/material.dart';
import '../../data/mock_data.dart';
import '../widgets/story_list_item.dart';

class StoriesPage extends StatelessWidget {
  const StoriesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final stories = MockData.getMockStories();

    return Scaffold(
      appBar: AppBar(title: const Text('故事'), elevation: 0),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: stories.length,
        itemBuilder: (context, index) {
          return StoryListItem(story: stories[index]);
        },
      ),
    );
  }
}
