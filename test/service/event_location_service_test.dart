import 'package:flutter_test/flutter_test.dart';
import 'package:photo_album/service/event/event_location_service.dart';

void main() {
  group('EventLocationService.shouldResolvePhotoLocation', () {
    test('returns false when event photo count is below threshold', () {
      final shouldResolve = EventLocationService.shouldResolvePhotoLocation(
        eventPhotoCount: 4,
        isLocationProcessed: false,
        latitude: 22.5431,
        longitude: 114.0579,
        minPhotosForDisplay: 5,
      );

      expect(shouldResolve, isFalse);
    });

    test('returns false when already processed', () {
      final shouldResolve = EventLocationService.shouldResolvePhotoLocation(
        eventPhotoCount: 5,
        isLocationProcessed: true,
        latitude: 22.5431,
        longitude: 114.0579,
        minPhotosForDisplay: 5,
      );

      expect(shouldResolve, isFalse);
    });

    test('returns false when GPS is incomplete', () {
      final withoutLat = EventLocationService.shouldResolvePhotoLocation(
        eventPhotoCount: 5,
        isLocationProcessed: false,
        latitude: null,
        longitude: 114.0579,
        minPhotosForDisplay: 5,
      );
      final withoutLon = EventLocationService.shouldResolvePhotoLocation(
        eventPhotoCount: 5,
        isLocationProcessed: false,
        latitude: 22.5431,
        longitude: null,
        minPhotosForDisplay: 5,
      );

      expect(withoutLat, isFalse);
      expect(withoutLon, isFalse);
    });

    test('returns true when all conditions are met', () {
      final shouldResolve = EventLocationService.shouldResolvePhotoLocation(
        eventPhotoCount: 5,
        isLocationProcessed: false,
        latitude: 22.5431,
        longitude: 114.0579,
        minPhotosForDisplay: 5,
      );

      expect(shouldResolve, isTrue);
    });
  });
}
