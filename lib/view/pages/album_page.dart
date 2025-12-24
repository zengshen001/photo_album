import 'package:flutter/material.dart';
import '../../data/mock_data.dart';
import '../widgets/event_card.dart';

class AlbumPage extends StatelessWidget {
  const AlbumPage({super.key});

  @override
  Widget build(BuildContext context) {
    final groupedEvents = MockData.getGroupedEvents();

    return Scaffold(
      appBar: AppBar(title: const Text('相册'), elevation: 0),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: groupedEvents.entries.map((entry) {
          final seasonTitle = entry.key;
          final events = entry.value;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  seasonTitle,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              ...events.map((event) => EventCard(event: event)),
              const SizedBox(height: 0),
            ],
          );
        }).toList(),
      ),
    );
  }
}
