import '../../utils/event/event_cluster_helper.dart';

class ClusterPhotoSnapshot {
  final int id;
  final int timestamp;
  final double? latitude;
  final double? longitude;
  final String? city;
  final String? province;
  final String? adcode;

  const ClusterPhotoSnapshot({
    required this.id,
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.city,
    required this.province,
    required this.adcode,
  });

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'timestamp': timestamp,
      'latitude': latitude,
      'longitude': longitude,
      'city': city,
      'province': province,
      'adcode': adcode,
    };
  }

  factory ClusterPhotoSnapshot.fromMap(Map<String, dynamic> map) {
    return ClusterPhotoSnapshot(
      id: map['id'] as int,
      timestamp: map['timestamp'] as int,
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      city: map['city'] as String?,
      province: map['province'] as String?,
      adcode: map['adcode'] as String?,
    );
  }
}

class ClusterConfigSnapshot {
  final int initialTimeThresholdHours;
  final double baseDistanceThresholdKm;
  final int sameCityTimeThresholdHours;
  final double sameCityDistanceThresholdKm;
  final double fallbackSameCityDistanceKm;
  final int sameDayMergeGapHours;
  final int crossDayMergeGapHours;
  final int minPhotosPerClusterForMerge;
  final bool enableSameDayTravelMerge;
  final bool enableCrossDayTravelMerge;
  final bool enableFestivalClustering;
  final int festivalMergeGapHours;
  final String festivalListVersion;

  const ClusterConfigSnapshot({
    required this.initialTimeThresholdHours,
    required this.baseDistanceThresholdKm,
    required this.sameCityTimeThresholdHours,
    required this.sameCityDistanceThresholdKm,
    required this.fallbackSameCityDistanceKm,
    required this.sameDayMergeGapHours,
    required this.crossDayMergeGapHours,
    required this.minPhotosPerClusterForMerge,
    required this.enableSameDayTravelMerge,
    required this.enableCrossDayTravelMerge,
    required this.enableFestivalClustering,
    required this.festivalMergeGapHours,
    required this.festivalListVersion,
  });

  factory ClusterConfigSnapshot.fromClusterConfig(ClusterConfig config) {
    return ClusterConfigSnapshot(
      initialTimeThresholdHours: config.initialTimeThresholdHours,
      baseDistanceThresholdKm: config.baseDistanceThresholdKm,
      sameCityTimeThresholdHours: config.sameCityTimeThresholdHours,
      sameCityDistanceThresholdKm: config.sameCityDistanceThresholdKm,
      fallbackSameCityDistanceKm: config.fallbackSameCityDistanceKm,
      sameDayMergeGapHours: config.sameDayMergeGapHours,
      crossDayMergeGapHours: config.crossDayMergeGapHours,
      minPhotosPerClusterForMerge: config.minPhotosPerClusterForMerge,
      enableSameDayTravelMerge: config.enableSameDayTravelMerge,
      enableCrossDayTravelMerge: config.enableCrossDayTravelMerge,
      enableFestivalClustering: config.enableFestivalClustering,
      festivalMergeGapHours: config.festivalMergeGapHours,
      festivalListVersion: config.festivalListVersion,
    );
  }

  ClusterConfig toClusterConfig() {
    return ClusterConfig(
      initialTimeThresholdHours: initialTimeThresholdHours,
      baseDistanceThresholdKm: baseDistanceThresholdKm,
      sameCityTimeThresholdHours: sameCityTimeThresholdHours,
      sameCityDistanceThresholdKm: sameCityDistanceThresholdKm,
      fallbackSameCityDistanceKm: fallbackSameCityDistanceKm,
      sameDayMergeGapHours: sameDayMergeGapHours,
      crossDayMergeGapHours: crossDayMergeGapHours,
      minPhotosPerClusterForMerge: minPhotosPerClusterForMerge,
      enableSameDayTravelMerge: enableSameDayTravelMerge,
      enableCrossDayTravelMerge: enableCrossDayTravelMerge,
      enableFestivalClustering: enableFestivalClustering,
      festivalMergeGapHours: festivalMergeGapHours,
      festivalListVersion: festivalListVersion,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'initialTimeThresholdHours': initialTimeThresholdHours,
      'baseDistanceThresholdKm': baseDistanceThresholdKm,
      'sameCityTimeThresholdHours': sameCityTimeThresholdHours,
      'sameCityDistanceThresholdKm': sameCityDistanceThresholdKm,
      'fallbackSameCityDistanceKm': fallbackSameCityDistanceKm,
      'sameDayMergeGapHours': sameDayMergeGapHours,
      'crossDayMergeGapHours': crossDayMergeGapHours,
      'minPhotosPerClusterForMerge': minPhotosPerClusterForMerge,
      'enableSameDayTravelMerge': enableSameDayTravelMerge,
      'enableCrossDayTravelMerge': enableCrossDayTravelMerge,
      'enableFestivalClustering': enableFestivalClustering,
      'festivalMergeGapHours': festivalMergeGapHours,
      'festivalListVersion': festivalListVersion,
    };
  }

  factory ClusterConfigSnapshot.fromMap(Map<String, dynamic> map) {
    return ClusterConfigSnapshot(
      initialTimeThresholdHours: map['initialTimeThresholdHours'] as int,
      baseDistanceThresholdKm: (map['baseDistanceThresholdKm'] as num)
          .toDouble(),
      sameCityTimeThresholdHours: map['sameCityTimeThresholdHours'] as int,
      sameCityDistanceThresholdKm: (map['sameCityDistanceThresholdKm'] as num)
          .toDouble(),
      fallbackSameCityDistanceKm: (map['fallbackSameCityDistanceKm'] as num)
          .toDouble(),
      sameDayMergeGapHours: map['sameDayMergeGapHours'] as int,
      crossDayMergeGapHours: map['crossDayMergeGapHours'] as int,
      minPhotosPerClusterForMerge: map['minPhotosPerClusterForMerge'] as int,
      enableSameDayTravelMerge: map['enableSameDayTravelMerge'] as bool,
      enableCrossDayTravelMerge: map['enableCrossDayTravelMerge'] as bool,
      enableFestivalClustering: map['enableFestivalClustering'] as bool,
      festivalMergeGapHours: map['festivalMergeGapHours'] as int,
      festivalListVersion: map['festivalListVersion'] as String,
    );
  }
}

class ClusterComputeRequest {
  final List<ClusterPhotoSnapshot> photos;
  final ClusterConfigSnapshot config;

  const ClusterComputeRequest({required this.photos, required this.config});

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'photos': photos.map((photo) => photo.toMap()).toList(),
      'config': config.toMap(),
    };
  }

  factory ClusterComputeRequest.fromMap(Map<String, dynamic> map) {
    final photosRaw = map['photos'] as List<dynamic>;
    return ClusterComputeRequest(
      photos: photosRaw
          .map(
            (item) =>
                ClusterPhotoSnapshot.fromMap(item as Map<String, dynamic>),
          )
          .toList(),
      config: ClusterConfigSnapshot.fromMap(
        map['config'] as Map<String, dynamic>,
      ),
    );
  }
}

class ClusterComputeResponse {
  final List<List<int>> clusteredPhotoIds;
  final int initialClusterCount;
  final int mergedCount;

  const ClusterComputeResponse({
    required this.clusteredPhotoIds,
    required this.initialClusterCount,
    required this.mergedCount,
  });

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'clusteredPhotoIds': clusteredPhotoIds,
      'initialClusterCount': initialClusterCount,
      'mergedCount': mergedCount,
    };
  }

  factory ClusterComputeResponse.fromMap(Map<String, dynamic> map) {
    final clusteredPhotoIdsRaw = map['clusteredPhotoIds'] as List<dynamic>;
    return ClusterComputeResponse(
      clusteredPhotoIds: clusteredPhotoIdsRaw
          .map(
            (group) => (group as List<dynamic>).map((id) => id as int).toList(),
          )
          .toList(),
      initialClusterCount: map['initialClusterCount'] as int,
      mergedCount: map['mergedCount'] as int,
    );
  }
}
