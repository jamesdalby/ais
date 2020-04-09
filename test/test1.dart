import 'package:aisdecode/aishandler.dart';
import 'package:aisdecode/cpa.dart';

int main(args) {
  new AISTest(
      args[0],
      int.parse(args[1])
  ).run();
  return 0;
}

class AISTest extends AISHandler {
  AISTest(String host, int port) : super(host, port);

  void we(PCS us) {}

  void they(PCS us, PCS them, int mmsi) {
    double t = tcpa(us, them);
    double c = cpa(us, them, t);
    String ship = name(mmsi) ?? mmsi.toString();
    print(
        "$us -> $them\t"
            "$ship"
            " ${(t*60).toStringAsFixed(1)}mins"
            " ${c.toStringAsFixed(1)}nm"
    );
  }
}