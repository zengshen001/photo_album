import 'dart:async';
import 'dart:collection';

typedef AsyncJob<T> = Future<T> Function();

class ConcurrencyPool {
  final int maxConcurrent;
  final Queue<_QueuedJob<dynamic>> _queue = Queue<_QueuedJob<dynamic>>();
  int _running = 0;
  bool _closed = false;

  ConcurrencyPool({required this.maxConcurrent})
    : assert(maxConcurrent > 0, 'maxConcurrent must be > 0');

  int get running => _running;
  int get queued => _queue.length;
  bool get isClosed => _closed;

  Future<T> withPermit<T>(AsyncJob<T> job, {Duration? timeout}) {
    if (_closed) {
      return Future.error(StateError('ConcurrencyPool is closed'));
    }

    final completer = Completer<T>();
    final queued = _QueuedJob<T>(
      job: job,
      completer: completer,
      timeout: timeout,
    );
    _queue.add(queued);
    _drain();
    return completer.future;
  }

  void close() {
    _closed = true;
  }

  void _drain() {
    while (_running < maxConcurrent && _queue.isNotEmpty) {
      final next = _queue.removeFirst();
      _start(next);
    }
  }

  void _start<T>(_QueuedJob<T> queued) {
    _running++;

    () async {
      try {
        Future<T> future = queued.job();
        if (queued.timeout != null) {
          future = future.timeout(queued.timeout!);
        }
        final value = await future;
        if (!queued.completer.isCompleted) {
          queued.completer.complete(value);
        }
      } catch (e, st) {
        if (!queued.completer.isCompleted) {
          queued.completer.completeError(e, st);
        }
      } finally {
        _running--;
        _drain();
      }
    }();
  }
}

class _QueuedJob<T> {
  final AsyncJob<T> job;
  final Completer<T> completer;
  final Duration? timeout;

  _QueuedJob({
    required this.job,
    required this.completer,
    required this.timeout,
  });
}
