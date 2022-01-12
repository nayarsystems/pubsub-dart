import 'dart:async';

import 'package:meta/meta.dart';

final _subscriptions = <String, Set<Subscriber>>{};
final _sticky = <String, Message>{};
var _atomic = 0;

/// [Exception] that embeds [StackTrace] so it's not lost on [call] function
class StackException implements Exception {
  dynamic exception;
  StackTrace stackTrace;

  StackException(this.exception, this.stackTrace);
}

int publish(String to,
    {dynamic data, String? rpath, bool sticky = false, bool propagate = true}) {
  var msg = Message(to: to, resp: rpath, data: data);
  var touch = 0;
  if (sticky) {
    _sticky[msg.to] = msg._cloneSticky();
  }
  var chunks = msg.to.split('.');
  while (chunks.isNotEmpty) {
    var topic = chunks.join('.');
    if (_subscriptions.containsKey(topic)) {
      var subsTopic = _subscriptions[topic];

      if (subsTopic != null) {
        for (var sub in subsTopic) {
          sub._send(msg);
          if (!sub.hidden) {
            touch++;
          }
        }
      }
    }
    if (!propagate) break;
    chunks.removeLast();
  }
  return touch;
}

Future<dynamic> wait(List<String> topics,
    {bool sticky = true, Duration? timeout}) async {
  var stream = subscribe(topics).stream;

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

Future<dynamic> call(String to,
    {dynamic data, String? resp, Duration? timeout}) async {
  var rpath = resp ?? '#resp.${++_atomic}';

  var f = wait([rpath], sticky: false, timeout: timeout);
  publish(to, data: data, rpath: rpath, sticky: false);
  var ret = await f;
  if (ret is Exception || ret is Error) {
    if (ret is StackException) {
      throw await Future.error(ret.exception, ret.stackTrace);
    } else {
      throw ret;
    }
  }
  return ret;
}

Subscriber subscribe(List<String> topics, {bool hidden = false}) {
  return Subscriber(topics, hidden: hidden);
}

typedef MsgCb = void Function(Message msg);

/// Subscriber can be subscribed to subscription paths
class Subscriber {
  bool _closed = false;
  bool hidden = false;
  late StreamController<Message> _stc;
  final _localSubs = <String>{};

  Subscriber(List<String> topics, {this.hidden = false}) {
    _stc = StreamController();
    _stc.onCancel = () {
      close();
    };
    subscribeMany(topics);
  }

  Stream<Message> get stream {
    return _stc.stream;
  }

  Stream get streamData {
    return stream.map((Message msg) => msg.data);
  }

  bool get closed {
    return _closed;
  }

  void close() {
    if (!_closed) {
      _closed = true;
      unsubscribeAll();
      _stc.close();
    }
  }

  bool subscribe(String topic) {
    if (_closed) throw Exception('Subscribe on closed Subscriber');
    var ret = _subscriptions.putIfAbsent(topic, () => <Subscriber>{}).add(this);
    _localSubs.add(topic);
    if (_sticky.containsKey(topic)) {
      var stickyVal = _sticky[topic];
      if (stickyVal != null) {
        _send(stickyVal);
      }
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
      var sub = _subscriptions[topic];

      if (sub != null) {
        ret = sub.remove(this);
        if (sub.isEmpty) {
          _subscriptions.remove(topic);
        }
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
    if (!_closed) {
      _stc.add((msg));
    }
  }
}

/// Represents a message that can be published in a topic.
class Message {
  ///  Target topic.
  final String to;

  /// Response topic (Optional).
  final String? resp;

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

  Message._full(
      {required this.to,
      this.resp,
      required this.data,
      required this.sticky,
      required this.creation});

  /// Constructs a new [Message] instance.
  /// [to] is the target topic.
  /// [data] is the message data.
  /// [resp] is the optional response topic.
  Message({required String to, @required dynamic data, String? resp})
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
  /// If passing an [Exception]/[Error] use [StackException] to keep the [StackTrace] on [call]
  void answer(dynamic data) {
    var r = resp;
    if (r != null && r != '') {
      publish(r, data: data);
    }
  }

  @override
  String toString() {
    return 'Message(to:$to, data:$data, sticky:$sticky${resp != null ? ", resp:$resp" : ""})';
  }
}
