import 'package:flutter/material.dart';

class StoriesPage extends StatelessWidget {
  const StoriesPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Placeholder for now
    return Scaffold(
      appBar: AppBar(
        title: const Text('故事集'),
      ),
      body: const Center(
        child: Text(
          '目前还没有故事，赶紧去回忆里生成一个吧！',
          style: TextStyle(color: Colors.black54),
        ),
      ),
    );
  }
}
