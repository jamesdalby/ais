/// Closest point of approach, distance and time
import 'dart:math';
import 'aisdecode.dart';

/// Representation of Position, Course & Speed
///
/// This is used as parameters to the tcpa&cpa functions herein.
class PCS {
  /// latitude, degrees
  final double lat;

  /// longitude, degrees
  final double lon;

  /// course over the ground, degrees from North
  final double cog;

  /// speed over the ground, knots
  final double sog;

  /// northerly speed in degrees per hour, primarily for internal use
  final double ns;

  /// easterly speed in degrees per hour, primarily for internal use
  final double es;

  /// Position, Course and Speed
  ///
  /// [lat] and [lon] are position in degrees
  ///
  /// [cog] course over the ground, degrees from North
  ///
  /// [sog] speed over the ground, kn
  PCS(this.lat, this.lon, this.cog, this.sog)
      :
        ns = sog / 60 * cos(_deg2rad(cog)),
        es = sog / 60 * sin(_deg2rad(cog)) / cos(_deg2rad(lat)).abs();

  /// Location as [lat,lon] after [time] in hours
  List<double> at(double time) {
    return [
      lon + es * time, // es and ns are in (equator) degrees/hour
      lat + ns * time
    ];
  }

  static double _deg2rad(v) => v == null ? null : (v * pi / 180);

  String _latLon() {
    // dms accepts minutes, so *60
    return "(${dms(lat * 60, 'N', 'S', null)}, ${dms(
        lon * 60, 'E', 'W', null)})";
  }

  @override String toString() {
    return '${_latLon()} ${cog.toInt()}°@${sog.toStringAsFixed(1)}kn';
  }
}

double _dotProduct(List<double> a, List<double> b) {
  return a[0] * b[0] + a[1] * b[1];
}

/// Time in hours of CPA between [us] & [them]
///
/// To convert to minutes, just multiply by 60
///
/// Divergent courses will return negative
///
/// Parallel courses will return NaN
double tcpa(final PCS us, final PCS them) {
  var dv = [ us.es - them.es, us.ns - them.ns];
  double dv2 = _dotProduct(dv, dv);
  if (dv2 == 0) { return 0; }
  return -_dotProduct([ us.lon - them.lon, us.lat - them.lat], dv) / dv2;
}

/// Closest point of approach in nm between [us] and [them]
///
/// If [time] given, this just computes distance at [time]
/// but if it's null it'll compute tcpa(us,them) and use that time
double cpa(final PCS us, final PCS them, [double time]) {
  return distance(us, them, time ?? tcpa(us, them));
}

/// Distance in nm between [us] & [them], [time] hours in the future
double distance(final PCS us, final PCS them, [final double time = 0]) {
  var ut = us.at(time);
  var tt = them.at(time);
  var dx = ut[0] - tt[0];
  var dy = ut[1] - tt[1];
  // dx, dy conceptually in degrees, so convert to nm (*60)
  return sqrt(dx * dx + dy * dy) * 60;
}
