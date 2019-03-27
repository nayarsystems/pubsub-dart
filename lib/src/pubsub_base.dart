import 'dart:async';

import 'package:meta/meta.dart';

final _subscriptions = Map<String, Set<Subscriber>>();
final _sticky = Map<String, Message>();
var _atomic = 0;

int publish(String to, dynamic data,
    {String rpath, bool sticky = false, bool propagate = true}) {
  var msg = Message(to: to, resp: rpath, data: data);
  var touch = 0;
  if (sticky) {
    _sticky[msg.to] = msg._cloneSticky();
  }
  var chunks = msg.to.split('.');
  while (chunks.isNotEmpty) {
    var topic = chunks.join('.');
    if (_subscriptions.containsKey(topic)) {
      for (var sub in _subscriptions[topic]) {
        sub._send(msg);
        if (!sub.hidden) {
          touch++;
        }
      }
    }
    if (!propagate) break;
    chunks.removeLast();
  }
  return touch;
}

Future<dynamic> wait(String topic,
    {bool sticky = true, Duration timeout}) async {
  var stream = subscribe([topic]).stream;

  if (timeout != null) {
    stream = stream.timeout(timeout, onTimeout: (EventSink ev) {
      ev.close();
    });
  }

  await for (Message msg in stream) {
    if (!sticky && msg.sticky) continue;
    return msg.data;
  }
  throw (TimeoutException('Timeout on wait function'));
}

Future<dynamic> call(String to, dynamic data,
    {String resp, Duration timeout}) async {
  var rpath = resp ?? '#resp.${++_atomic}';

  var f = wait(rpath, sticky: false, timeout: timeout);
  publish(to, data, rpath: rpath, sticky: false);
  var ret = await f;
  if (ret is Exception) throw (ret);
  return ret;
}

Subscriber subscribe(List<String> topics, {bool hidden = false}) {
  return Subscriber(topics, hidden: hidden);
}

typedef MsgCb = void Function(Message msg);

/// Subscriber can be subscribed to subscription paths
class Subscriber {
  bool _closed = false;
  bool _hidden = false;
  StreamController<Message> _stc;
  final _localSubs = Set<String>();

  Subscriber(List<String> topics, {bool hidden = false}) {
    _hidden = hidden;
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

  Stream get streamData {
    return stream.map((Message msg) => msg.data);
  }

  bool get hidden {
    return _hidden;
  }

  set hidden(bool hid) {
    _hidden = hid;
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
    if (_closed) throw Exception('Subscribe on closed Subscriber');
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
    if (_closed) throw Exception('Unsubscribe on closed Subscriber');
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

/// Represents a message that can be published in a topic.
class Message {
  ///  Target topic.
  final String to;

  /// Response topic (Optional).
  final String resp;

  /// Creation time
  final int creation;

  /// Message data.
  final dynamic data;

  /// Sticky messages remain in memory and are delivered when a subscriber
  /// subscribes to the topic to which the sticky message was previously delivered.
  /// You can check if a message is recent or old by looking at the state of this flag.
  final bool sticky;

  static Message fromMap(dynamic m) {
    if (m is Message) return m;

    return Message._full(
      to: m['to'],
      resp: m['resp'],
      data: m['data'],
      sticky: m['sticky'] ?? false,
      creation: m['creation'] ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'to': to,
      'resp': resp,
      'data': data,
      'sticky': sticky,
      'creation': creation,
    };
  }

  Message._full({this.to, this.resp, this.data, this.sticky, this.creation});

  /// Constructs a new [Message] instance.
  /// [to] is the target topic.
  /// [data] is the message data.
  /// [resp] is the optional response topic.
  Message({@required String to, @required dynamic data, String resp})
      : this._full(
            to: to,
            resp: resp,
            data: data,
            sticky: false,
            creation: DateTime.now().millisecondsSinceEpoch);

  Message _cloneSticky() {
    return Message._full(
        to: to, resp: resp, data: data, sticky: true, creation: creation);
  }

  /// create and publish a [Message] in response to this one.
  /// This message must have a non-null [resp] field.
  void answer(Object data) {
    if (resp != null && resp != '') {
      publish(resp, data);
    }
  }

  String toString() {
    return 'Message(to:$to, data:$data${sticky != null ? ", sticky:$sticky" : ""}${resp != null ? ", resp:$resp" : ""})';
  }
}
