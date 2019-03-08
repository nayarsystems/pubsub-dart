import 'dart:async';

final _subscriptions = Map<String, Set<Subscriber>>();
final _sticky = Map<String, Message>();
var _atomic = 0;

int publish(Message msg, {bool sticky = false, bool propagate = true}) {
  var touch = 0;
  if (sticky) {
    _sticky[msg.to] = msg.clone(isSticky: true);
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
    Duration timeout}) {
  var rpath = resp ?? '#resp.${++_atomic}';
  var msg = Message(to: to, resp: rpath, data: data);
  var completer = Completer<Object>();
  Timer tout;

  var sub = Subscriber();
  sub.stream.listen((msg) {
    if (!completer.isCompleted) {
      if (msg.data is Exception) {
        completer.completeError(msg.data);
      } else {
        completer.complete(msg.data);
      }
    }
    sub.close();
    tout?.cancel();
  });

  sub.subscribe(rpath);

  if (timeout != null) {
    tout = Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.completeError(TimeoutException("PubSub call timeout"));
        sub.unsubscribeAll();
      }
    });
  }

  publish(msg, sticky: sticky, propagate: propagate);

  return completer.future;
}

typedef MsgCb = void Function(Message msg);

/// Subscriber can be subscribed to subscription paths
class Subscriber {
  bool _closed = false;
  StreamController<Message> _stc;
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

  Stream<Message> get stream {
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

class Message {
  final String to;
  final String resp;
  final DateTime creation;
  final Object data;
  final bool sticky;

  Message({this.to, this.resp, this.data, this.sticky = false})
      : creation = DateTime.now();

  Message clone({bool isSticky}) {
    return Message(to: to, resp: resp, data: data, sticky: isSticky ?? sticky);
  }

  void respond(Object data) {
    if (resp != null) {
      publish(Message(to: resp, data: data), propagate: false);
    }
  }
}
