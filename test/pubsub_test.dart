import 'package:pubsub/pubsub.dart';
import 'package:test/test.dart';

void main() {
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
      PubSub.publish(Message(to: "sota", data: "Hello"));
      expect(messagesA.length, 1);
      expect(messagesA[0].to, "sota");
      expect(messagesA[0].data, "Hello");
      PubSub.publish(Message(to: "sota.caballo", data: "Hello"));
      expect(messagesA.length, 2);
      expect(messagesA[1].to, "sota.caballo");
      expect(messagesA[1].data, "Hello");
      PubSub.publish(Message(to: "caballo", data: "Hello"));
      expect(messagesA.length, 2);
    });

    test("Multiple subscription test", () {
      subA.subscribeMany(["sota", "caballo"]);
      subB.subscribeMany(["caballo", "rey"]);
      expect(PubSub.publish(Message(to: "rey", data: "Hello")), 1);
      expect(messagesA.length, 0);
      expect(messagesB.length, 1);
      expect(PubSub.publish(Message(to: "sota", data: "Hello")), 1);
      expect(messagesA.length, 1);
      expect(messagesB.length, 1);
      expect(PubSub.publish(Message(to: "caballo", data: "Hello")), 2);
      expect(messagesA.length, 2);
      expect(messagesB.length, 2);
    });

    test("Unsubscribe test", () {
      expect(subA.subscribe("sota"), true);
      expect(PubSub.publish(Message(to: "sota", data: "Hello")), 1);
      expect(messagesA.length, 1);
      expect(subA.unsubscribe("sota"), true);
      expect(PubSub.publish(Message(to: "sota", data: "Hello")), 0);
      expect(messagesA.length, 1);
    });

    test("Unsubscribe all test", () {
      expect(subA.subscribe("sota"), true);
      expect(subA.subscribe("caballo"), true);
      expect(PubSub.publish(Message(to: "sota", data: "Hello")), 1);
      expect(PubSub.publish(Message(to: "caballo", data: "Hello")), 1);
      expect(messagesA.length, 2);
      subA.unsubscribeAll();
      expect(PubSub.publish(Message(to: "sota", data: "Hello")), 0);
      expect(PubSub.publish(Message(to: "caballo", data: "Hello")), 0);
      expect(messagesA.length, 2);
    });

    test("Parents propagate test", () {
      expect(subA.subscribe("sota"), true);
      expect(subB.subscribe("sota.caballo"), true);
      expect(
          PubSub.publish(Message(to: "sota.caballo", data: "Hello"),
              propagate: false),
          1);
      expect(messagesA.length, 0);
      expect(messagesB.length, 1);
      expect(PubSub.publish(Message(to: "sota.caballo", data: "Hello")), 2);
      expect(messagesA.length, 1);
      expect(messagesB.length, 2);
    });

    test("Sticky messages test", () {
      PubSub.publish(Message(to: "sota", data: "Hello"), sticky: true);
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
  });
}
