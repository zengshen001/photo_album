import 'package:flutter_test/flutter_test.dart';

import 'package:photo_album/utils/concurrency/concurrency_pool.dart';

void main() {
  test(
    'ConcurrencyPool enforces max concurrency and does not deadlock on errors',
    () async {
      final pool = ConcurrencyPool(maxConcurrent: 2);
      var running = 0;
      var maxObserved = 0;

      Future<void> trackedDelay([int ms = 50]) async {
        running++;
        maxObserved = maxObserved < running ? running : maxObserved;
        await Future<void>.delayed(Duration(milliseconds: ms));
        running--;
      }

      final jobs = <Future<void>>[];
      for (var i = 0; i < 5; i++) {
        jobs.add(pool.withPermit(() async => trackedDelay()));
      }
      jobs.add(
        pool
            .withPermit(() async {
              await trackedDelay(10);
              throw StateError('boom');
            })
            .then((_) {}, onError: (_) {}),
      );
      jobs.add(pool.withPermit(() async => trackedDelay()));

      await Future.wait(jobs);
      expect(maxObserved, lessThanOrEqualTo(2));
    },
  );

  test('ConcurrencyPool releases permit on timeout', () async {
    final pool = ConcurrencyPool(maxConcurrent: 1);
    final first = pool
        .withPermit(
          () async => Future<void>.delayed(const Duration(milliseconds: 80)),
          timeout: const Duration(milliseconds: 10),
        )
        .catchError((_) {});

    final second = pool.withPermit(
      () async => Future<void>.delayed(const Duration(milliseconds: 10)),
      timeout: const Duration(milliseconds: 100),
    );

    await first;
    await second;
  });
}
