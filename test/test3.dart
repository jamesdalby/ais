
import 'package:ais/geom.dart';

int main(var args) {
  final double alat = 50.1, alon = -1.3, blat = 50.4, blon = -1.6;
  print(range(alat,alon,blat,blon).toStringAsFixed(1));
  print(bearing(alat,alon,blat,blon).toStringAsFixed(1));
  return 0;
}