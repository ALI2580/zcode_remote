import 'dart:async';

/// Protocol notifications do not require a widget runtime. UI owners subscribe
/// and publish their own Flutter state at the application boundary.
abstract interface class ProtocolListenable {
  void addListener(void Function() listener);
  void removeListener(void Function() listener);
}

abstract interface class ProtocolValueListenable<T>
    implements ProtocolListenable {
  T get value;
}

class _Listener {
  _Listener(this.callback);
  final void Function() callback;
  bool active = true;
}

class ProtocolNotifier implements ProtocolListenable {
  final _listeners = <_Listener>[];
  bool _disposed = false;

  @override
  void addListener(void Function() listener) {
    if (_disposed) throw StateError('protocol notifier disposed');
    _listeners.add(_Listener(listener));
  }

  @override
  void removeListener(void Function() listener) {
    final index = _listeners.indexWhere((item) => item.callback == listener);
    if (index < 0) return;
    _listeners.removeAt(index).active = false;
  }

  void notifyListeners() {
    if (_disposed) return;
    for (final listener in List<_Listener>.of(_listeners)) {
      if (_disposed) break;
      if (!listener.active) continue;
      try {
        listener.callback();
      } catch (error, stack) {
        Zone.current.handleUncaughtError(error, stack);
      }
    }
  }

  void dispose() {
    _disposed = true;
    _listeners.clear();
  }
}

class ValueSignal<T> extends ProtocolNotifier
    implements ProtocolValueListenable<T> {
  ValueSignal(this._value);
  T _value;
  @override
  T get value => _value;
  set value(T next) {
    if (_value == next) return;
    _value = next;
    notifyListeners();
  }
}
