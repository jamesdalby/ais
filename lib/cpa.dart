/// Closest point of approach, distance and time
import 'dart:math';
import 'aisdecode.dart';
import 'geom.dart';

/// Representation of Position, Course & Speed
///
/// This is used as parameters to the tcpa&cpa functions herein.
class PCS {
  /// latitude, degrees
  final double? lat;

  /// longitude, degrees
  final double? lon;

  // Lat & Long in nice format
  String? get latLon => _latLon();

  /// course over the ground, degrees from North
  final double? cog;

  /// speed over the ground, knots
  final double? sog;

  double _ns;

  /// northerly speed in degrees per hour, primarily for internal use
  double get ns => _ns;

  double _es;

  /// easterly speed in degrees per hour, primarily for internal use
  double get es => _es;

  /// Position, Course and Speed
  ///
  /// [lat] and [lon] are position in degrees
  ///
  /// [cog] course over the ground, degrees from North
  ///
  /// [sog] speed over the ground, kn
  PCS(this.lat, this.lon, this.cog, this.sog) : _es = 0, _ns = 0 {
    if (cog != null && sog != null && lat != null) {
      _ns = sog! / 60 * cos(_deg2rad(cog));
      _es = sog! / 60 * sin(_deg2rad(cog)) / cos(_deg2rad(lat)).abs();
    }
  }

  /// Location as [lat,lon] after [time] in hours
  List<double>? at(final double time) {
    if (lat==null || lon==null) return null;
    if (time == 0) { return [lon!,lat!]; }
    return [
      lon! + _es * time, // es and ns are in (equator) degrees/hour
      lat! + _ns * time
    ];
  }

  static double _deg2rad(v) => v == null ? null : (v * pi / 180);

  String? _latLon() {
    // dms accepts minutes, so *60
    if (lat == null || lon == null) {
      return null;
    }
    return "${dms(lat! * 60, 'N', 'S')} ${dms(lon! * 60, 'E', 'W')}";
  }

  @override String toString() {
    String ll = _latLon() ?? 'NoPos';
    if (cog != null) ll += " ${cog!.toInt()}°";
    if (sog != null) ll += " ${sog!.toStringAsFixed(1)}kn";

    return ll;
  }

  /// bearing in degrees from North to them
  double? bearingTo(final PCS them) {
    if (lat == null  || lon == null || them.lat == null || them.lon == null) return null;
    return bearing(lat!, lon!, them.lat!, them.lon!);
  }

  // distance from us to them in nm
  double? distanceTo(final PCS them) {
    return distance(this, them);
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
///
/// If our COG is null, this returns null.
double? tcpa(final PCS us, final PCS them) {
  if (us.cog == null) { return null; }
  if (us.lon==null || us.lat==null) return null;
  if (them.lon==null || them.lat==null) return null;
  var dv = [ us.es - them.es, us.ns - them.ns];
  double dv2 = _dotProduct(dv, dv);
  if (dv2 == 0) { return 0; }
  return -_dotProduct([ us.lon! - them.lon!, us.lat! - them.lat!], dv) / dv2;
}

/// Closest point of approach in nm between [us] and [them]
///
/// If [time] given, this just computes distance at [time]
/// but if it's null it'll compute tcpa(us,them) and use that time
///
/// If our COG is null, this returns null
double? cpa(final PCS us, final PCS them, [double? time]) {
  return distance(us, them, time ?? tcpa(us, them));
}

/// Distance in nm between [us] & [them], [time] hours in the future.
///
/// If our COG is null, then this returns null
double? distance(final PCS us, final PCS them, [final double? time = 0]) {
  if (us.cog == null || time == null) {
    return null;
  }
  List<double>? ut = us.at(time);
  List<double>? tt = them.at(time);
  if (ut == null || tt == null) return null;

  var dx = ut[0] - tt[0];
  var dy = ut[1] - tt[1];
  // dx, dy conceptually in degrees, so convert to nm (*60)
  return sqrt(dx * dx + dy * dy) * 60;
}


