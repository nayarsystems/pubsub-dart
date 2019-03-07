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
      for (var sub in _subscriptions[path].toList()) {
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
  sub.setCb((msg) {
    if (!completer.isCompleted) {
      if (msg.data is Exception) {
        completer.completeError(msg.data);
      } else {
        completer.complete(msg.data);
      }
    }
    sub.unsubscribeAll();
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
  MsgCb _msgCb;
  StreamController<Message> _stc;
  final _localSubs = Set<String>();

  Subscriber([MsgCb cb]) {
    _msgCb = cb;
  }

  Stream<Message> get stream {
    if (_stc == null) {
      _stc = StreamController();
    }
    return _stc.stream;
  }

  void setCb(MsgCb cb) {
    _msgCb = cb;
  }

  bool subscribe(String path) {
    var ret =
        _subscriptions.putIfAbsent(path, () => Set<Subscriber>()).add(this);
    _localSubs.add(path);
    if (_sticky.containsKey(path)) {
      _send(_sticky[path]);
    }
    return ret;
  }

  void subscribeMany(List<String> paths) {
    for (var path in paths) {
      subscribe(path);
    }
  }

  bool unsubscribe(String path) {
    var ret = false;
    if (_subscriptions.containsKey(path)) {
      ret = _subscriptions[path].remove(this);
      if (_subscriptions[path].isEmpty) {
        _subscriptions.remove(path);
      }
      _localSubs.remove(path);
    }
    return ret;
  }

  void unsubscribeMany(List<String> paths) {
    for (var path in paths) {
      unsubscribe(path);
    }
  }

  void unsubscribeAll() {
    for (var path in _localSubs.toList()) {
      unsubscribe(path);
    }
  }

  void _send(Message msg) {
    if (_msgCb != null) {
      _msgCb(msg);
    }

    if (_stc != null) {
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
