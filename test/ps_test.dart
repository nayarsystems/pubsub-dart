import 'dart:async';
import 'package:ps/ps.dart';
import 'package:test/test.dart';

main() {
  group('Subscriber test', () {
    Subscriber subA;
    Subscriber subB;
    var messagesA = List<Message>();
    var messagesB = List<Message>();

    Future<dynamic> contextSwitch() {
      return Future.delayed(const Duration(seconds: 0));
    }

    msgCbA(Message msg) {
      messagesA.add(msg);
    }

    msgCbB(Message msg) {
      messagesB.add(msg);
    }

    setUp(() {
      subA = Subscriber();
      subB = Subscriber();
      messagesA.clear();
      messagesB.clear();
    });

    tearDown(() {
      subA.close();
      subB.close();
    });

    test("Single subscription test", () async {
      subA.stream.listen(msgCbA);
      expect(subA.subscribe("sota"), true);
      publish(Message(to: "sota", data: "Hello"));
      await contextSwitch();
      expect(messagesA.length, 1);
      expect(messagesA[0].to, "sota");
      expect(messagesA[0].data, "Hello");
      publish(Message(to: "sota.caballo", data: "Hello"));
      await contextSwitch();
      expect(messagesA.length, 2);
      expect(messagesA[1].to, "sota.caballo");
      expect(messagesA[1].data, "Hello");
      publish(Message(to: "caballo", data: "Hello"));
      await contextSwitch();
      expect(messagesA.length, 2);
    });

    test("Multiple subscription test", () async {
      subA.stream.listen(msgCbA);
      subB.stream.listen(msgCbB);
      subA.subscribeMany(["sota", "caballo"]);
      subB.subscribeMany(["caballo", "rey"]);
      expect(publish(Message(to: "rey", data: "Hello")), 1);
      await contextSwitch();
      expect(messagesA.length, 0);
      expect(messagesB.length, 1);
      expect(publish(Message(to: "sota", data: "Hello")), 1);
      await contextSwitch();
      expect(messagesA.length, 1);
      expect(messagesB.length, 1);
      expect(publish(Message(to: "caballo", data: "Hello")), 2);
      await contextSwitch();
      expect(messagesA.length, 2);
      expect(messagesB.length, 2);
    });

    test("Unsubscribe test", () async {
      subA.stream.listen(msgCbA);
      expect(subA.subscribe("sota"), true);
      expect(publish(Message(to: "sota", data: "Hello")), 1);
      await contextSwitch();
      expect(messagesA.length, 1);
      expect(subA.unsubscribe("sota"), true);
      expect(publish(Message(to: "sota", data: "Hello")), 0);
      await contextSwitch();
      expect(messagesA.length, 1);
    });

    test("Unsubscribe all test", () async {
      subA.stream.listen(msgCbA);
      expect(subA.subscribe("sota"), true);
      expect(subA.subscribe("caballo"), true);
      expect(publish(Message(to: "sota", data: "Hello")), 1);
      expect(publish(Message(to: "caballo", data: "Hello")), 1);
      await contextSwitch();
      expect(messagesA.length, 2);
      subA.unsubscribeAll();
      expect(publish(Message(to: "sota", data: "Hello")), 0);
      expect(publish(Message(to: "caballo", data: "Hello")), 0);
      await contextSwitch();
      expect(messagesA.length, 2);
    });

    test("Parents propagate test", () async {
      subA.stream.listen(msgCbA);
      subB.stream.listen(msgCbB);
      expect(subA.subscribe("sota"), true);
      expect(subB.subscribe("sota.caballo"), true);
      expect(
          publish(Message(to: "sota.caballo", data: "Hello"), propagate: false),
          1);
      await contextSwitch();
      expect(messagesA.length, 0);
      expect(messagesB.length, 1);
      expect(publish(Message(to: "sota.caballo", data: "Hello")), 2);
      await contextSwitch();
      expect(messagesA.length, 1);
      expect(messagesB.length, 2);
    });

    test("Sticky messages test", () async {
      subA.stream.listen(msgCbA);
      publish(Message(to: "__sticky__", data: "Hello"), sticky: true);
      subA.subscribe("__sticky__");
      await contextSwitch();
      expect(messagesA.length, 1);
      expect(messagesA[0].sticky, true);
    });

    test("Subscriber stream", () async {
      var sub = Subscriber(["sota"]);
      var stream = sub.stream;
      expect(publish(Message(to: "sota", data: 1)), 1);
      expect(publish(Message(to: "sota", data: 2)), 1);
      var list = await stream.take(2).toList();
      expect(list[0].data, 1);
      expect(list[1].data, 2);
      expect(sub.closed, true);
    });

    test("Async call", () async {
      subA.stream.listen((msg) {
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
