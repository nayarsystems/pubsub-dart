import 'dart:async';
import 'package:ps/ps.dart';
import 'package:test/test.dart';

main() {
  group('Subscriber test', () {
    Subscriber subA;
    Subscriber subB;
    var messagesA = List<Message>();
    var messagesB = List<Message>();

    msgCbA(Message msg) {
      messagesA.add(msg);
    }

    msgCbB(Message msg) {
      messagesB.add(msg);
    }

    setUp(() {
      subA = Subscriber(msgCbA);
      subB = Subscriber(msgCbB);
      messagesA.clear();
      messagesB.clear();
    });

    tearDown(() {
      subA.unsubscribeAll();
      subB.unsubscribeAll();
    });

    test("Single subscription test", () {
      expect(subA.subscribe("sota"), true);
      publish(Message(to: "sota", data: "Hello"));
      expect(messagesA.length, 1);
      expect(messagesA[0].to, "sota");
      expect(messagesA[0].data, "Hello");
      publish(Message(to: "sota.caballo", data: "Hello"));
      expect(messagesA.length, 2);
      expect(messagesA[1].to, "sota.caballo");
      expect(messagesA[1].data, "Hello");
      publish(Message(to: "caballo", data: "Hello"));
      expect(messagesA.length, 2);
    });

    test("Multiple subscription test", () {
      subA.subscribeMany(["sota", "caballo"]);
      subB.subscribeMany(["caballo", "rey"]);
      expect(publish(Message(to: "rey", data: "Hello")), 1);
      expect(messagesA.length, 0);
      expect(messagesB.length, 1);
      expect(publish(Message(to: "sota", data: "Hello")), 1);
      expect(messagesA.length, 1);
      expect(messagesB.length, 1);
      expect(publish(Message(to: "caballo", data: "Hello")), 2);
      expect(messagesA.length, 2);
      expect(messagesB.length, 2);
    });

    test("Unsubscribe test", () {
      expect(subA.subscribe("sota"), true);
      expect(publish(Message(to: "sota", data: "Hello")), 1);
      expect(messagesA.length, 1);
      expect(subA.unsubscribe("sota"), true);
      expect(publish(Message(to: "sota", data: "Hello")), 0);
      expect(messagesA.length, 1);
    });

    test("Unsubscribe all test", () {
      expect(subA.subscribe("sota"), true);
      expect(subA.subscribe("caballo"), true);
      expect(publish(Message(to: "sota", data: "Hello")), 1);
      expect(publish(Message(to: "caballo", data: "Hello")), 1);
      expect(messagesA.length, 2);
      subA.unsubscribeAll();
      expect(publish(Message(to: "sota", data: "Hello")), 0);
      expect(publish(Message(to: "caballo", data: "Hello")), 0);
      expect(messagesA.length, 2);
    });

    test("Parents propagate test", () {
      expect(subA.subscribe("sota"), true);
      expect(subB.subscribe("sota.caballo"), true);
      expect(
          publish(Message(to: "sota.caballo", data: "Hello"), propagate: false),
          1);
      expect(messagesA.length, 0);
      expect(messagesB.length, 1);
      expect(publish(Message(to: "sota.caballo", data: "Hello")), 2);
      expect(messagesA.length, 1);
      expect(messagesB.length, 2);
    });

    test("Sticky messages test", () {
      publish(Message(to: "sota", data: "Hello"), sticky: true);
      subA.subscribe("sota");
      expect(messagesA.length, 1);
      expect(messagesA[0].sticky, true);
    });

    test("Message clone", () {
      var msg1 = Message(to: "sota");
      var msg2 = msg1.clone();
      expect(msg2.sticky, false);
      var msg3 = msg2.clone(isSticky: true);
      expect(msg3.sticky, true);
    });

    test("Subscriber stream", () async {
      expect(subA.subscribe("sota"), true);
      var stream = subA.stream;
      expect(publish(Message(to: "sota", data: 1)), 1);
      expect(publish(Message(to: "sota", data: 2)), 1);
      var list = await stream.take(2).toList();
      expect(list[0].data, 1);
      expect(list[1].data, 2);
    });

    test("Async call", () async {
      subA.setCb((msg) {
        switch (msg.data) {
          case 1:
            msg.respond("Hello");
            break;
          case 2:
            msg.respond(Exception("Boom!!"));
            break;
        }
      });

      subA.subscribe("say.hello");
      expect(await call("say.hello", 1), "Hello");
      try {
        await call("say.hello", 2);
        fail("Exception expected");
      } catch (e) {
        expect(e.toString(), contains("Boom!!"));
      }

      try {
        await call("say.bay", null, timeout: Duration(milliseconds: 5));
        fail("Timeout exception expected");
      } catch (e) {
        expect(e is TimeoutException, true,
            reason: "Expected TimeoutException");
      }
    });
  });
}