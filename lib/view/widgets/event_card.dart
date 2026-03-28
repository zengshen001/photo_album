import 'package:flutter/material.dart';

import '../../models/event.dart';
import '../pages/event_detail_page.dart';
import 'movie_poster_stack.dart';

class EventCard extends StatelessWidget {
  final Event event;

  const EventCard({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    final coverPhoto = event.coverPhotos.isNotEmpty
        ? event.coverPhotos.first
        : null;
    final subtitle = event.isFestivalEvent && event.festivalName != null
        ? event.festivalName
        : event.tags.take(3).join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: MoviePosterStack(
          title: event.title,
          subtitle: subtitle?.isEmpty ?? true ? null : subtitle,
          topBadge: '${event.photos.length} 张',
          metaLine: '${event.dateRangeText} · ${event.location}',
          path: coverPhoto?.path,
          assetId: coverPhoto?.id,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => EventDetailPage(event: event),
              ),
            );
          },
          background: coverPhoto == null
              ? Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF2C2C2E), Color(0xFF111113)],
                    ),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.photo_library_outlined,
                      size: 48,
                      color: Colors.white70,
                    ),
                  ),
                )
              : null,
        ),
      ),
    );
  }
}
