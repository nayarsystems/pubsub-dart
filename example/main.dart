import 'package:ps/ps.dart';

void main() {
  subscribe(['topic']).stream.listen((msg) {
    print('Received: $msg');
  });
  publish('topic', 'Some data');
}
