import 'dart:collection';

/// Capture mutations where existing view models are intentionally route-owned.
class RecoveryMap<K, V> extends MapBase<K, V> {
  RecoveryMap(this.changed, {this.added});
  final void Function() changed;
  final void Function(V)? added;
  final _data = <K, V>{};
  @override
  V? operator [](Object? key) => _data[key];
  @override
  void operator []=(K key, V value) {
    if (_data.containsKey(key) && _data[key] == value) return;
    _data[key] = value;
    added?.call(value);
    changed();
  }

  @override
  Iterable<K> get keys => _data.keys;
  @override
  V? remove(Object? key) {
    if (!_data.containsKey(key)) return null;
    final value = _data.remove(key);
    changed();
    return value;
  }

  @override
  void clear() {
    if (_data.isEmpty) return;
    _data.clear();
    changed();
  }
}

class RecoverySet<E> extends SetBase<E> {
  RecoverySet(this.changed);
  final void Function() changed;
  final _data = <E>{};
  @override
  bool add(E value) {
    final result = _data.add(value);
    if (result) changed();
    return result;
  }

  @override
  bool remove(Object? value) {
    final result = _data.remove(value);
    if (result) changed();
    return result;
  }

  @override
  bool contains(Object? element) => _data.contains(element);
  @override
  E? lookup(Object? element) => _data.lookup(element);
  @override
  Iterator<E> get iterator => _data.iterator;
  @override
  int get length => _data.length;
  @override
  Set<E> toSet() => _data.toSet();
}
