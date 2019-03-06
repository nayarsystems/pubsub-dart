import 'dart:async';

class PubSub {
  static final _subscriptions = Map<String, Set<Subscriber>>();
  static final _sticky = Map<String, Message>();

  static bool _addSubscription(String path, Subscriber sub) {
    return _subscriptions.putIfAbsent(path, () => Set<Subscriber>()).add(sub);
  }

  static bool _delSubscription(String path, Subscriber sub) {
    var ret = false;
    if (_subscriptions.containsKey(path)) {
      ret = _subscriptions[path].remove(sub);
      if (_subscriptions[path].isEmpty) {
        _subscriptions.remove(path);
      }
    }
    return ret;
  }

  static int publish(Message msg,
      {bool sticky = false, bool propagate = true}) {
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
}

typedef MsgCb = void Function(Message msg);

/// Subscriber can be subscribed to subscription paths
class Subscriber {
  MsgCb _msgCb;
  StreamController _stc;
  final _subscriptions = Set<String>();

  Subscriber([MsgCb cb]) {
    _msgCb = cb;
  }

  Stream<Message> get stream {
    if (_stc == null) {
      _stc = StreamController();
    }
    return _stc.stream;
  }

  bool subscribe(String path) {
    var ret = PubSub._addSubscription(path, this);
    if (ret) {
      _subscriptions.add(path);
    }
    if (PubSub._sticky.containsKey(path)) {
      _send(PubSub._sticky[path]);
    }
    return ret;
  }

  void subscribeMany(List<String> paths) {
    for (var path in paths) {
      subscribe(path);
    }
  }

  bool unsubscribe(String path) {
    var ret = PubSub._delSubscription(path, this);
    if (ret) {
      _subscriptions.remove(path);
    }
    return ret;
  }

  void unsubscribeMany(List<String> paths) {
    for (var path in paths) {
      unsubscribe(path);
    }
  }

  void unsubscribeAll() {
    for (var path in _subscriptions.toList()) {
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

  Message({this.to, this.resp = '', this.data, this.sticky = false})
      : creation = DateTime.now();

  Message clone({bool isSticky}) {
    return Message(to: to, resp: resp, data: data, sticky: isSticky ?? sticky);
  }
}
