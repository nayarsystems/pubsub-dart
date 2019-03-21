import 'dart:async';
import 'package:ps/ps.dart';
import 'package:test/test.dart';

main() {
  group('Subscriber test', () {
    test("Single subscription test", () async {
      var sub = subscribe(["sota", "sota.*"]);
      expect(publish("sota", "Hello"), 1);
      expect(publish("sota.caballo", "Bye"), 1);
      expect(publish("caballo", "Hello"), 0);
      sub.close();
      var list = await sub.stream.toList();
      expect(list.length, 2);
      expect(list[0].to, "sota");
      expect(list[0].data, "Hello");
      expect(list[1].to, "sota.caballo");
      expect(list[1].data, "Bye");
    });

    test("Hidden subscription test", () async {
      var sub = subscribe(["sota"], hidden: true);
      expect(publish("sota", "Hello"), 0);
      sub.hidden = false;
      expect(publish("sota", "Hello"), 1);
      sub.close();
    });

    test("Multiple subscription test", () async {
      var sub1 = subscribe(["sota", "caballo"]);
      var sub2 = subscribe(["caballo", "rey"]);
      expect(publish("rey", "M1"), 1);
      expect(publish("sota", "M2"), 1);
      expect(publish("caballo", "M3"), 2);
      sub1.close();
      sub2.close();
      var list1 = await sub1.stream.toList();
      var list2 = await sub2.stream.toList();
      expect(list1.length, 2);
      expect(list1[0].to, "sota");
      expect(list1[0].data, "M2");
      expect(list1[1].to, "caballo");
      expect(list1[1].data, "M3");
      expect(list2.length, 2);
      expect(list2[0].to, "rey");
      expect(list2[0].data, "M1");
      expect(list2[1].to, "caballo");
      expect(list2[1].data, "M3");
    });

    test("Unsubscribe test", () async {
      var sub = subscribe(["sota"]);
      expect(publish("sota", "Hello"), 1);
      expect(sub.unsubscribe("sota"), true);
      expect(publish("sota", "Hello"), 0);
      sub.close();
      await sub.stream.toList();
    });

    test("Unsubscribe all test", () async {
      var sub = subscribe(["sota", "caballo"]);
      expect(publish("sota", "Hello"), 1);
      expect(publish("caballo", "Hello"), 1);
      sub.unsubscribeAll();
      expect(publish("sota", "Hello"), 0);
      expect(publish("caballo", "Hello"), 0);
      sub.close();
      await sub.stream.toList();
    });

    test("Parents propagate test", () async {
      var sub1 = subscribe(["sota.*"]);
      var sub2 = subscribe(["sota.caballo"]);
      expect(publish("sota.caballo", "Hello", propagate: false), 1);
      expect(publish("sota.caballo", "Hello"), 2);
      sub1.close();
      sub2.close();
      var list1 = await sub1.stream.toList();
      var list2 = await sub2.stream.toList();
      expect(list1.length, 1);
      expect(list2.length, 2);
    });

    test("Sticky messages test", () async {
      publish("__sticky__", "Hello", sticky: true);
      var sub = subscribe(["__sticky__"]);
      sub.close();
      var list = await sub.stream.toList();
      expect(list.length, 1);
      expect(list[0].sticky, true);
    });

    test("Async call", () async {
      var stream = subscribe(["say.hello"]).stream;
      var ss = stream.listen((msg) {
        switch (msg.data) {
          case 1:
            msg.answer("Hello");
            break;
          case 2:
            msg.answer(Exception("Boom!!"));
            break;
        }
      });

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
      await ss.cancel();
    });
  });
}
