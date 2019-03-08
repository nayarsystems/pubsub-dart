import 'dart:async';

final _subscriptions = Map<String, Set<Subscriber>>();
final _sticky = Map<String, Message>();
var _atomic = 0;

int publish(Message msg, {bool sticky = false, bool propagate = true}) {
  var touch = 0;
  if (sticky) {
    _sticky[msg.to] = msg._cloneSticky();
  }
  var chunks = msg.to.split('.');
  while (chunks.isNotEmpty) {
    var path = chunks.join('.');
    if (_subscriptions.containsKey(path)) {
      for (var sub in _subscriptions[path]) {
        sub._send(msg);
        touch++;
      }
    }
    if (!propagate) break;
    chunks.removeLast();
  }
  return touch;
}

Future<Object> call(String to, Object data,
    {String resp,
    bool sticky = false,
    bool propagate = false,
    Duration timeout}) async {
  var rpath = resp ?? '#resp.${++_atomic}';
  var msg = Message(to: to, resp: rpath, data: data);

  var stream = Subscriber([rpath]).stream;
  publish(msg, sticky: sticky, propagate: propagate);
  Message ret;
  if (timeout == null) {
    ret = await stream.first;
  } else {
    ret = await stream.first.timeout(timeout);
  }
  if (ret.data is Exception) throw (ret.data);
  return ret.data;
}

Subscriber<T> subscribe<T>([List<String> topics]) {
  return Subscriber<T>(topics);
}

typedef MsgCb = void Function(Message msg);

/// Subscriber can be subscribed to subscription paths
class Subscriber<T> {
  bool _closed = false;
  StreamController<Message<T>> _stc;
  final _localSubs = Set<String>();

  Subscriber([List<String> topics]) {
    _stc = StreamController();
    _stc.onCancel = () {
      close();
    };
    if (topics != null) {
      subscribeMany(topics);
    }
  }

  Stream<Message<T>> get stream {
    return _stc.stream;
  }

  bool get closed {
    return _closed;
  }

  void close() {
    if (!_closed) {
      _closed = true;
      unsubscribeAll();
      _stc?.close();
    }
  }

  bool subscribe(String topic) {
    if (_closed) throw Exception("Subscribe on closed Subscriber");
    var ret =
        _subscriptions.putIfAbsent(topic, () => Set<Subscriber>()).add(this);
    _localSubs.add(topic);
    if (_sticky.containsKey(topic)) {
      _send(_sticky[topic]);
    }
    return ret;
  }

  void subscribeMany(List<String> topics) {
    for (var topic in topics) {
      subscribe(topic);
    }
  }

  bool unsubscribe(String topic) {
    var ret = false;
    if (_subscriptions.containsKey(topic)) {
      ret = _subscriptions[topic].remove(this);
      if (_subscriptions[topic].isEmpty) {
        _subscriptions.remove(topic);
      }
      _localSubs.remove(topic);
    }
    return ret;
  }

  void unsubscribeMany(List<String> topics) {
    if (_closed) throw Exception("Unsubscribe on closed Subscriber");
    for (var topic in topics) {
      unsubscribe(topic);
    }
  }

  void unsubscribeAll() {
    for (var topic in _localSubs.toList()) {
      unsubscribe(topic);
    }
  }

  void _send(Message msg) {
    if (!_closed && _stc != null) {
      _stc.add((msg));
    }
  }
}

class Message<T> {
  final String to;
  final String resp;
  final DateTime creation;
  final T data;
  final bool sticky;

  Message._full({this.to, this.resp, this.data, this.sticky})
      : creation = DateTime.now();

  Message({String to, String resp, T data})
      : this._full(to: to, resp: resp, data: data, sticky: false);

  Message<T> _cloneSticky() {
    return Message<T>._full(to: to, resp: resp, data: data, sticky: true);
  }

  void respond(Object data) {
    if (resp != null) {
      publish(Message(to: resp, data: data), propagate: false);
    }
  }
}
