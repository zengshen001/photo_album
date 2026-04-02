import 'dart:async';

import 'package:dio/dio.dart';
import 'package:isar/isar.dart';

import '../../models/entity/event_entity.dart';
import '../../models/entity/photo_entity.dart';
import '../../utils/concurrency/concurrency_pool.dart';
import '../photo/photo_service.dart';

class EventLocationService {
  static const int _eventLocationResolveBatchSize = 10;
  static const int _photoLocationResolveBatchSize = 20;
  static const int _maxRetries = 3;
  static const Duration _eventResolveTimeout = Duration(seconds: 12);
  static const Duration _photoResolveTimeout = Duration(seconds: 12);

  final String amapWebKey;
  final int minPhotosForDisplay;
  final Dio _dio;
  final ConcurrencyPool pool;

  EventLocationService({
    required this.amapWebKey,
    required this.minPhotosForDisplay,
    required this.pool,
    Dio? dio,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 10),
               receiveTimeout: const Duration(seconds: 10),
               sendTimeout: const Duration(seconds: 10),
               responseType: ResponseType.json,
             ),
           );

  static bool shouldResolvePhotoLocation({
    required int eventPhotoCount,
    required bool isLocationProcessed,
    required double? latitude,
    required double? longitude,
    required int minPhotosForDisplay,
  }) {
    return eventPhotoCount >= minPhotosForDisplay &&
        !isLocationProcessed &&
        latitude != null &&
        longitude != null;
  }

  Future<void> resolveEventLocations({
    required Isar isar,
    Set<int>? onlyEventIds,
  }) async {
    if (amapWebKey.trim().isEmpty) {
      print("⚠️ AMAP_WEB_KEY 未配置，跳过地址解析");
      return;
    }

    while (true) {
      final events = await _queryEventsForLocationResolve(
        isar: isar,
        onlyEventIds: onlyEventIds,
      );

      if (events.isEmpty) {
        print("✅ 所有事件地址已解析完成");
        return;
      }

      print("🌏 开始解析 ${events.length} 个事件地址...");
      await Future.wait(
        events.map(
          (event) => pool.withPermit(
            () => _resolveSingleEventLocation(isar: isar, event: event),
            timeout: _eventResolveTimeout,
          ),
        ),
      );
    }
  }

  Future<void> resolvePhotoLocationsForVisibleEvents({
    required Isar isar,
    Set<int>? onlyEventIds,
  }) async {
    if (amapWebKey.trim().isEmpty) {
      return;
    }

    while (true) {
      final visibleEvents = await _queryVisibleEvents(
        isar: isar,
        onlyEventIds: onlyEventIds,
      );
      if (visibleEvents.isEmpty) {
        return;
      }

      final eventPhotoCountById = {
        for (final event in visibleEvents) event.id: event.photoCount,
      };
      final photos = await _queryPhotosForLocationResolve(
        isar: isar,
        eventIds: visibleEvents.map((event) => event.id).toList(),
      );
      if (photos.isEmpty) {
        return;
      }

      print("🌏 开始逐图解析地址，本批次: ${photos.length} 张");
      final tasks = <Future<void>>[];
      for (final photo in photos) {
        if (_hasSavedPhotoLocation(photo)) {
          tasks.add(_markPhotoLocationProcessed(isar: isar, photoId: photo.id));
          continue;
        }

        final eventPhotoCount = eventPhotoCountById[photo.eventId];
        if (eventPhotoCount == null ||
            !shouldResolvePhotoLocation(
              eventPhotoCount: eventPhotoCount,
              isLocationProcessed: photo.isLocationProcessed,
              latitude: photo.latitude,
              longitude: photo.longitude,
              minPhotosForDisplay: minPhotosForDisplay,
            )) {
          continue;
        }

        tasks.add(
          pool.withPermit(
            () => _resolveSinglePhotoLocation(isar: isar, photo: photo),
            timeout: _photoResolveTimeout,
          ),
        );
      }
      if (tasks.isEmpty) {
        return;
      }
      await Future.wait(tasks);
    }
  }

  Future<List<EventEntity>> _queryEventsForLocationResolve({
    required Isar isar,
    Set<int>? onlyEventIds,
  }) async {
    var events = await isar
        .collection<EventEntity>()
        .filter()
        .avgLatitudeIsNotNull()
        .photoCountGreaterThan(minPhotosForDisplay - 1)
        .cityIsNull()
        .limit(_eventLocationResolveBatchSize)
        .findAll();
    if (onlyEventIds == null || onlyEventIds.isEmpty) {
      return events;
    }
    return events.where((event) => onlyEventIds.contains(event.id)).toList();
  }

  Future<void> _resolveSingleEventLocation({
    required Isar isar,
    required EventEntity event,
  }) async {
    for (var attempt = 1; attempt <= _maxRetries; attempt++) {
      try {
        print(
          "开始解析事件地址: id=${event.id} lat=${event.avgLatitude} lon=${event.avgLongitude} attempt=$attempt/$_maxRetries",
        );
        final regeocode = await _reverseGeocodeWithAmap(
          latitude: event.avgLatitude!,
          longitude: event.avgLongitude!,
          extensions: 'base',
        );
        final data = regeocode['addressComponent'];
        if (data is! Map<String, dynamic>) {
          throw Exception('高德返回缺少addressComponent');
        }

        final province = _extractNonEmptyString(data, ['province']);
        String? city = _extractNonEmptyString(data, ['city']);
        city ??= _extractNonEmptyString(data, ['district']);
        city ??= province;
        final adcode = _extractNonEmptyString(data, ['adcode']);
        final citycode = _extractNonEmptyString(data, ['citycode']);

        await isar.writeTxn(() async {
          final latest = await isar.collection<EventEntity>().get(event.id);
          if (latest == null) return;
          latest.province = province;
          latest.city = city;
          if (latest.city != null &&
              latest.city!.isNotEmpty &&
              !latest.isLlmGenerated &&
              !latest.isFestivalEvent) {
            latest.title = "${latest.city} · ${latest.dateRangeText}";
          }
          await isar.collection<EventEntity>().put(latest);
        });

        print(
          "📍 事件地址解析成功: ${event.title} -> ${city ?? province ?? '未知地点'} "
          "(adcode=${adcode ?? '-'} citycode=${citycode ?? '-'})",
        );
        return;
      } catch (e) {
        print("❌ 地址解析失败: $e");
        if (attempt == _maxRetries) {
          await isar.writeTxn(() async {
            final latest = await isar.collection<EventEntity>().get(event.id);
            if (latest == null) return;
            latest.city ??= '未知地点';
            await isar.collection<EventEntity>().put(latest);
          });
          return;
        }
        await Future<void>.delayed(
          Duration(milliseconds: 250 * (1 << attempt)),
        );
      }
    }
  }

  Future<List<EventEntity>> _queryVisibleEvents({
    required Isar isar,
    Set<int>? onlyEventIds,
  }) async {
    var events = await isar
        .collection<EventEntity>()
        .filter()
        .photoCountGreaterThan(minPhotosForDisplay - 1)
        .findAll();
    if (onlyEventIds == null || onlyEventIds.isEmpty) {
      return events;
    }
    return events.where((event) => onlyEventIds.contains(event.id)).toList();
  }

  bool _hasSavedPhotoLocation(PhotoEntity photo) {
    return (photo.formattedAddress?.isNotEmpty ?? false) ||
        (photo.city?.isNotEmpty ?? false) ||
        (photo.province?.isNotEmpty ?? false) ||
        (photo.district?.isNotEmpty ?? false) ||
        (photo.adcode?.isNotEmpty ?? false);
  }

  Future<void> _markPhotoLocationProcessed({
    required Isar isar,
    required Id photoId,
  }) async {
    var didUpdate = false;
    await isar.writeTxn(() async {
      final latest = await isar.collection<PhotoEntity>().get(photoId);
      if (latest == null || latest.isLocationProcessed) {
        return;
      }
      latest.isLocationProcessed = true;
      await isar.collection<PhotoEntity>().put(latest);
      didUpdate = true;
    });
    if (didUpdate) {
      PhotoService().markLocalDataChanged();
    }
  }

  Future<List<PhotoEntity>> _queryPhotosForLocationResolve({
    required Isar isar,
    required List<int> eventIds,
  }) {
    return isar
        .collection<PhotoEntity>()
        .filter()
        .anyOf(eventIds, (q, eventId) => q.eventIdEqualTo(eventId))
        .isLocationProcessedEqualTo(false)
        .latitudeIsNotNull()
        .longitudeIsNotNull()
        .limit(_photoLocationResolveBatchSize)
        .findAll();
  }

  Future<Map<String, int>> getLocationProgress({
    required Isar isar,
    Set<int>? onlyEventIds,
  }) async {
    final visibleEvents = await _queryVisibleEvents(
      isar: isar,
      onlyEventIds: onlyEventIds,
    );
    if (visibleEvents.isEmpty) {
      return {
        'eventTotal': 0,
        'eventWithCity': 0,
        'photoTotal': 0,
        'photoProcessed': 0,
        'photoPending': 0,
      };
    }

    final eventIds = visibleEvents.map((e) => e.id).toList();
    final eventTotal = visibleEvents.length;
    final eventWithCity = visibleEvents
        .where((e) => (e.city?.isNotEmpty ?? false))
        .length;

    final photoTotal = await isar
        .collection<PhotoEntity>()
        .filter()
        .anyOf(eventIds, (q, eventId) => q.eventIdEqualTo(eventId))
        .latitudeIsNotNull()
        .longitudeIsNotNull()
        .count();
    final photoProcessed = await isar
        .collection<PhotoEntity>()
        .filter()
        .anyOf(eventIds, (q, eventId) => q.eventIdEqualTo(eventId))
        .latitudeIsNotNull()
        .longitudeIsNotNull()
        .isLocationProcessedEqualTo(true)
        .count();

    return {
      'eventTotal': eventTotal,
      'eventWithCity': eventWithCity,
      'photoTotal': photoTotal,
      'photoProcessed': photoProcessed,
      'photoPending': photoTotal - photoProcessed,
    };
  }

  Future<void> _resolveSinglePhotoLocation({
    required Isar isar,
    required PhotoEntity photo,
  }) async {
    for (var attempt = 1; attempt <= _maxRetries; attempt++) {
      try {
        final lat = photo.latitude!;
        final lon = photo.longitude!;
        final regeocode = await _reverseGeocodeWithAmap(
          latitude: lat,
          longitude: lon,
          extensions: 'all',
        );
        final addressComponent = regeocode['addressComponent'];
        if (addressComponent is! Map<String, dynamic>) {
          throw Exception('高德返回缺少addressComponent');
        }

        final formattedAddress = _extractNonEmptyString(regeocode, [
          'formatted_address',
        ]);
        final district = _extractNonEmptyString(addressComponent, ['district']);
        final adcode = _extractNonEmptyString(addressComponent, ['adcode']);
        final province = _extractNonEmptyString(addressComponent, ['province']);
        String? city = _extractNonEmptyString(addressComponent, ['city']);
        city ??= district;
        city ??= province;

        var didUpdate = false;
        await isar.writeTxn(() async {
          final latest = await isar.collection<PhotoEntity>().get(photo.id);
          if (latest == null) return;
          latest.province = province;
          latest.city = city;
          latest.district = district;
          latest.adcode = adcode;
          latest.formattedAddress = formattedAddress;
          latest.isLocationProcessed = true;
          await isar.collection<PhotoEntity>().put(latest);
          didUpdate = true;
        });
        if (didUpdate) {
          PhotoService().markLocalDataChanged();
        }

        print(
          "📌 照片地址解析成功: id=${photo.id} city=${city ?? '-'} district=${district ?? '-'}",
        );
        return;
      } catch (e) {
        print("❌ 照片地址解析失败: id=${photo.id} attempt=$attempt error=$e");
        if (attempt == _maxRetries) {
          await _markPhotoLocationProcessed(isar: isar, photoId: photo.id);
          return;
        }
        await Future<void>.delayed(
          Duration(milliseconds: 250 * (1 << attempt)),
        );
      }
    }
  }

  Future<Map<String, dynamic>> _reverseGeocodeWithAmap({
    required double latitude,
    required double longitude,
    String extensions = 'base',
  }) async {
    final response = await _dio.get(
      'https://restapi.amap.com/v3/geocode/regeo',
      queryParameters: {
        'key': amapWebKey,
        'location': '$longitude,$latitude',
        'extensions': extensions,
        'coordsys': 'gps',
      },
    );

    final body = response.data;
    _logAmapResponseSummary(body);

    if (body is! Map<String, dynamic>) {
      throw Exception('高德返回格式异常');
    }

    if (body['status'] != '1') {
      throw Exception('高德返回失败: ${body['info'] ?? '未知错误'}');
    }

    final regeocode = body['regeocode'];
    if (regeocode is! Map<String, dynamic>) {
      throw Exception('高德返回缺少regeocode');
    }
    return regeocode;
  }

  void _logAmapResponseSummary(dynamic body) {
    if (body is! Map<String, dynamic>) {
      print("高德地图返回值(非Map): ${body.runtimeType}");
      return;
    }

    final status = body['status'];
    final info = body['info'];
    final regeocode = body['regeocode'];

    String? formattedAddress;
    String? city;
    String? district;
    String? adcode;
    if (regeocode is Map<String, dynamic>) {
      formattedAddress = _extractNonEmptyString(regeocode, [
        'formatted_address',
      ]);
      final addressComponent = regeocode['addressComponent'];
      if (addressComponent is Map<String, dynamic>) {
        city = _extractNonEmptyString(addressComponent, ['city']);
        district = _extractNonEmptyString(addressComponent, ['district']);
        adcode = _extractNonEmptyString(addressComponent, ['adcode']);
      }
    }

    print(
      "高德返回: status=$status info=${info ?? '-'} "
      "city=${city ?? '-'} district=${district ?? '-'} adcode=${adcode ?? '-'} "
      "addr=${formattedAddress ?? '-'}",
    );
  }

  String? _extractNonEmptyString(
    Map<String, dynamic> source,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = source[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
      if (value is List && value.isNotEmpty) {
        final first = value.first;
        if (first is String && first.trim().isNotEmpty) {
          return first.trim();
        }
      }
    }
    return null;
  }
}
