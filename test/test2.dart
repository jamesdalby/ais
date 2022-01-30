import 'package:ais/aishandler.dart';
import 'package:ais/cpa.dart';

int main(args) {
  new AISTest(
      args[0],
      int.parse(args[1])
  ).run();
  return 0;
}

class AISTest extends AISHandler {
  AISTest(final String host, final int port) : super(host, port);

  void we(final PCS us) {
    // print (us.toString());
  }

  Set<String> _seen = Set();

  void they(PCS us, PCS them, int mmsi) {
    /*double t = tcpa(us, them);
    double c = cpa(us, them, t);*/
    String ship = mmsi.toString(); // name(mmsi);
    if (_seen.contains(ship)) return;
    _seen.add(ship);
    print("$ship");
  }
}
