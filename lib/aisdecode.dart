/// Decode AIS payloads into class structures
import 'aistypes.dart';
export 'aistypes.dart';
import 'dart:math';

// This code needs no documentation; there is the very finest documentation available at
// https://gpsd.gitlab.io/gpsd/AIVDM.html

/*
  PAYLOAD ARMOURING
  u   Unsigned integer
  U   Unsigned integer with scale - renders as float, suffix is decimal places
  i   Signed integer
  I   Signed integer with scale - renders as float, suffix is decimal places
  b   Boolean
  e   Enumerated type (controlled vocabulary)
  x   Spare or reserved bit
  t   String (packed six-bit ASCII)
  d   Data (uninterpreted binary)
  a   Array boundary, numeric suffix is maximum array size. ^ before suffix means preceding fields is the length. Following fields are repeated to end of message
*/
int _decode(final String s, final int pos) {
  if (s.length <= pos) {
    return null;
  }
  int ch = s.codeUnitAt(pos) - 48;
  if (ch > 40) { ch -= 8; }
  return ch;
}

double _unsignedDouble(final String buf, final int start, final int len, final int scale) {
  return _unsignedInt(buf, start, len)*pow(10,-scale);
}

// extract [len] bits from [buf] starting at position [start]
// each byte in buf contains 6 bits of data (see _decode)
// return the resulting bits as an unsigned int
int _unsignedInt(final String buf, final int start, final int len) {
  int ret = 0;
  int s = start;
  int acc = 0;
  for (int n=s; n<start+len; ) {
    int byte = n~/6;
    int v = _decode(buf, byte);
    if (v == null) { return null; }
    int offset = n%6;
    int ll = min(len-acc, 6-offset);
    int shift = 6-offset-ll;
    int mask = (1<<ll)-1;
    v = (v >> shift) & mask;

    ret = (ret << ll) | v;

    n+=ll;
    acc+=ll;
  }
  return ret;
}

int _int(final String buf, final int start, final int len) {
  return _unsignedInt(buf, start,len).toSigned(len);
}

double _double(final String buf, final int start, final int len, final int scale) {
  return _int(buf, start,len)*pow(10, -scale);
}

bool _bool(final String buf, int start) {
  return _unsignedInt(buf, start, 1) == 1;
}

T _enumeration<T>(final String buf, int start, int len, List<T> values) {
  int i = _unsignedInt(buf, start,len);
  if (i == null || i < 0 || i >= values.length) { return null; }
  return values[i];
}

String _text(final String buf, final int start, final int len) {
  // len must be a multiple of 6
  String ret = "";
  for (int i=0; i<len; i+=6) {
    int v = _unsignedInt(buf, start+i, 6);
    if (v == null) { break; }
    ret += String.fromCharCode(v<32 ? 64+v : v);
  }
  return ret.replaceFirst(RegExp(r'@.*'), '').trim();
}

// Base class whence specific AIS messages are derived
class AIS {
  final String buf;
  final int pad;
  final int type;

  AIS._(this.buf, this.pad, this.type);

  factory AIS.from(final String s, { final int pad : 0 }) {
    int type = _unsignedInt(s, 0, 6);
    if (type == null) return null;
    switch (type) {
      case 1:  return Type1(s, pad);
      case 2:  return Type2(s, pad);  //
      case 3:  return Type3(s, pad);
      case 5:  return Type5(s, pad);
      case 18: return Type18(s, pad); // B
      case 21: return Type21(s, pad); // E
      case 24: {                      // H
        int partNo = _unsignedInt(s, 38, 2);
        return (partNo == 0) ? Type24A(s, pad) : Type24B(s, pad);
      }
      default:
        print("Unknown message type $type");
    }
    return null; // throw?
  }
}

/*
Table 6. Common Navigation Block
6-7 2 Repeat Indicator repeat u Message repeat count
8-37 30 MMSI mmsi u 9 decimal digits
38-41 4 Navigation Status status e See "Navigation Status"
42-49 8 Rate of Turn (ROT) turn I3
50-59 10 Speed Over Ground (SOG) speed U1
60-60 1 Position Accuracy accuracy b
61-88 28 Longitude lon I4 Minutes/10000 (see below)
89-115 27 Latitude lat I4 Minutes/10000 (see below)
116-127 12 Course Over Ground (COG) course U1 Relative to true north, to 0.1 degree precision
128-136 9 True Heading (HDG) heading u 0 to 359 degrees, 511 = not available.
137-142 6 Time Stamp second u Second of UTC timestamp
143-144 2 Maneuver Indicator maneuver e
145-147 3 Spare x Not used
148-148 1 RAIM flag raim b
149-167 19 Radio status radio u
*/
class CNB extends AIS {
  final int repeat;
  final int mmsi;
  final NavigationStatus status;
  final double turn;
  final double _sog;
  final bool accuracy;
  final double lon;
  final double lat;
  final double _course;
  final int heading;
  final int _second;
  final ManeuverIndicator maneuver;
  final bool raim;
  final int radio;

  String get lons => dms(lon, 'E', 'W', 181);
  String get lats => dms(lat, 'N', 'S', 91);
  int get second => _second >= 60 ? null : _second;
  double get course => _course == 360.0 ? null : _course;
  double get sog => _sog == 102.3 ? null : _sog;

  CNB(final String buf, final int pad, final int type) :
        repeat = _unsignedInt(buf, 6, 2),
        mmsi = _unsignedInt(buf, 8,30),
        status = _enumeration(buf, 38,4, NavigationStatus.values),
        turn = _double(buf, 42,8,3),
        _sog = _unsignedDouble(buf, 50,10,1),
        accuracy = _bool(buf, 60),
        lon = _double(buf, 61,28,4),
        lat = _double(buf, 89,27,4),
        _course = _unsignedDouble(buf, 116,12,1),
        heading = _unsignedInt(buf, 128,9),
        _second = _unsignedInt(buf, 137,6),
        maneuver = _enumeration(buf, 143,2, ManeuverIndicator.values),
        raim = _bool(buf, 148),
        radio = _unsignedInt(buf, 149,19),
        super._(buf, pad, type);

  @override String toString() {
    return 'CNB{repeat: $repeat, mmsi: $mmsi, status: $status, turn: $turn, sog: $sog, accuracy: $accuracy, lon: $lon ($lons), lat: $lat ($lats), course: $course, heading: $heading, second: $second, maneuver: $maneuver, raim: $raim, radio: $radio}';
  }
}

/// Convert [v] in MINUTES (note) to a nice string form
///
/// [p] is the suffix to be used if v is positive (N or E)
///
/// [n] is the suffix to be used if v is negative (S or W)
///
/// If [v] == [na] then this is assumed to be invalid and 'n/a' is returned
///
/// [dp] is the number of decimal places or minutes to be returned
///
String dms(double v, final String p, final String n, [final double na, final int dp=1]) {
  if (v == na) { return "n/a"; }
  String pn = p;
  if (v < 0) {
    v = -v;
    pn = n;
  }
  int d = v ~/ 60;
  double m = v - d*60;

  return "$d°${m.toStringAsFixed(dp)}$pn";
}

class Type1 extends CNB {
  Type1(final String buf, int pad) : super(buf, pad, 1);
  @override String toString() => 'Type1{${super.toString()}';
}

class Type2 extends CNB {
  Type2(final String buf, int pad) : super(buf, pad, 2);
  @override String toString() => "Type2{${super.toString()}}";
}

class Type3 extends CNB {
  Type3(final String buf, int pad) : super(buf, pad, 3);
  @override String toString() => "Type3{${super.toString()}}";
}

class Type5 extends AIS {
  final int repeat;
  final int mmsi;
  final int aisVersion;
  final int imo;
  final String callsign;
  final String shipname;
  final String shiptype;
  final int toBow;
  final int toStern;
  final int toPort;
  final int toStarboard;
  final String epfd;
  DateTime get eta => _eta(month, day, hour, minute);
  final int month, day, hour, minute;
  final double draught;
  final String	destination;
  final bool dte;

  Type5(final String buf, int pad) :
        repeat = _unsignedInt(buf, 6,2),
        mmsi = _unsignedInt(buf, 8,30),
        aisVersion = _unsignedInt(buf, 38,2),
        imo = _unsignedInt(buf, 40,30),
        callsign = _text(buf, 70, 42),
        shipname = _text(buf, 112, 120),
        shiptype = _enumeration(buf, 232, 8, ShipType),
        toBow = _unsignedInt(buf, 240,9),
        toStern = _unsignedInt(buf, 249, 9),
        toPort = _unsignedInt(buf, 258,6),
        toStarboard = _unsignedInt(buf, 264, 6),
        epfd = _enumeration(buf, 270, 4, FixType),
        month = _unsignedInt(buf, 274,4),
        day = _unsignedInt(buf, 278,5),
        hour = _unsignedInt(buf, 283,5),
        minute = _unsignedInt(buf, 288,6),
        draught = _unsignedDouble(buf, 294,8,1),
        destination = _text(buf, 392,120),
        dte = _bool(buf, 422),
        super._(buf, pad, 5);

  @override String toString() => '''Type5{
  repeat: $repeat, mmsi: $mmsi, ais_version: $aisVersion, imo: $imo, 
  callsign: $callsign, shipname: $shipname, shiptype: $shiptype,
  to_bow: $toBow, to_stern: $toStern, to_port: $toPort, to_starboard: $toStarboard, 
  epfd: $epfd, month: $month, day: $day, hour: $hour, minute: $minute, 
  draught: $draught, destination: $destination, dte: $dte
  }''';

  DateTime _eta(int month, int day, int hour, int minute) {
    DateTime now = DateTime.now();
    DateTime ret = DateTime.utc(now.year, month, day, hour, minute);
    if (ret.compareTo(now) < 0) {
      ret = DateTime.utc(now.year+1, month, day, hour, minute);
    }
    return ret;
  }
}

class Type18 extends AIS {
  final int repeat;
  final int mmsi;
  final double _speed; // sog in CNB
  final bool accuracy;
  final double lon;
  final double lat;
  final double _course;
  final int heading;
  final int _second;
  final int regional;
  final bool cs;
  final bool display;
  final bool dsc;
  final bool band;
  final bool msg22;
  final bool assigned;
  final bool raim;
  final int radio;

  Type18(final String buf, final int pad) :
        repeat = _unsignedInt(buf, 6, 2),
        mmsi = _unsignedInt(buf, 8, 30),
        _speed = _double(buf, 46, 10, 1),
        accuracy = _bool(buf, 56),
        lon = _double(buf, 57, 28, 4),
        lat = _double(buf, 85, 27, 4),
        _course = _unsignedDouble(buf, 112,12,1),
        heading = _unsignedInt(buf, 124, 9),
        _second = _unsignedInt(buf, 133, 6),
        regional = _unsignedInt(buf, 139, 2),
        cs = _bool(buf, 141),
        display = _bool(buf, 142),
        dsc = _bool(buf, 143),
        band = _bool(buf, 144),
        msg22 = _bool(buf, 145),
        assigned = _bool(buf, 146),
        raim = _bool(buf, 147),
        radio = _unsignedInt(buf, 148,20),
        super._(buf, pad, 18);

  String get lons => dms(lon, 'E', 'W', 181);
  String get lats => dms(lat, 'N', 'S', 91);
  int get second => _second >= 60 ? null : _second;
  double get course => _course == 360.0 ? null : _course;
  double get speed => _speed == 102.3 ? null : _speed;

  @override
  String toString() {
    return 'Type18{repeat: $repeat, mmsi: $mmsi, speed: $speed, accuracy: $accuracy, lon: $lon, lat: $lat, course: $course, heading: $heading, second: $second, regional: $regional, cs: $cs, display: $display, dsc: $dsc, band: $band, msg22: $msg22, assigned: $assigned, raim: $raim, radio: $radio}';
  }
}

class Type21 extends AIS {
  final int repeat;
  final int mmsi;
  final String aidType;
  final String name;
  final bool accuracy;
  final double lon;
  final double lat;
  final int toBow, toStern, toPort, toStarboard;
  final String epfd;
  final int second;
  final bool offPosition;
  final int regional;
  final bool raim;
  final bool virtualAid;
  final bool assigned;

  Type21(final String buf, final int pad)
      :
        repeat = _unsignedInt(buf, 6, 2),
        mmsi = _unsignedInt(buf, 8, 30),
        aidType = _enumeration(buf, 38, 5, AidType),
        name = _getName(buf),
        accuracy = _bool(buf, 163),
        lon = _double(buf, 164, 28, 4),
        lat = _double(buf, 192, 27, 4),
        toBow = _unsignedInt(buf, 219, 9),
        toStern = _unsignedInt(buf, 228, 9),
        toPort = _unsignedInt(buf, 237, 9),
        toStarboard = _unsignedInt(buf, 243, 9),
        epfd = _enumeration(buf, 249, 4, EPFDType),
        second = _unsignedInt(buf, 253, 6),
        offPosition = _bool(buf, 259),
        regional = _unsignedInt(buf, 260, 8),
        raim = _bool(buf, 268),
        virtualAid = _bool(buf, 269),
        assigned = _bool(buf, 270),
        super._(buf, pad, 21);

  static String _getName(final String buf)
  {
    String n = _text(buf, 43, 120);
    if (n.length == 20) {
      n = n + _text(buf, 272, 88);
    }
    return n;
  }

  @override
  String toString() {
    return 'Type21{repeat: $repeat, mmsi: $mmsi, aidType: $aidType, name: $name, accuracy: $accuracy, lon: $lon, lat: $lat, to_bow: $toBow, to_stern: $toStern, to_port: $toPort, to_starboard: $toStarboard, epfd: $epfd, second: $second, offPosition: $offPosition, regional: $regional, raim: $raim, virtualAid: $virtualAid, assigned: $assigned}';
  }


}

class Type24A extends AIS {
  final int repeat;
  final int mmsi;
  final int partno = 0;
  final String shipname;
  Type24A(final String buf, final int pad) :
        repeat = _unsignedInt(buf, 6, 2),
        mmsi = _unsignedInt(buf, 8, 30),
        shipname = _text(buf, 40, 120),
        super._(buf, pad, 24);

  @override
  String toString() {
    return 'Type24A{repeat: $repeat, mmsi: $mmsi, partno: $partno, shipname: $shipname}';
  }
}

class Type24B extends AIS {
  final int repeat;
  final int mmsi;
  final int partno = 1;

  final String shiptype;
  final String vendorid;
  final int model;
  final int serial;
  final String callsign;
  final int toBow, toStern, toPort, toStarboard;
  final int mothershipMMSI;

  Type24B(final String buf, final int pad) :
        repeat = _unsignedInt(buf, 6, 2),
        mmsi = _unsignedInt(buf, 8, 30),
        shiptype = _enumeration(buf, 40, 8, ShipType),
        vendorid = _text(buf, 48, 18),
        model = _unsignedInt(buf, 66, 4),
        serial = _unsignedInt(buf, 70,20),
        callsign = _text(buf, 90, 42),

        // only valid if mmsi is not 98XXXYYYY
        toBow = _unsignedInt(buf, 132, 9),
        toStern = _unsignedInt(buf, 141, 9),
        toPort = _unsignedInt(buf, 150, 6),
        toStarboard= _unsignedInt(buf, 156, 6),

        // only valid if mmsi is 98XXXYYYY
        mothershipMMSI = _unsignedInt(buf, 132,30),

        super._(buf, pad, 24);

  @override
  String toString() {
    return 'Type24B{repeat: $repeat, mmsi: $mmsi, partno: $partno, shiptype: $shiptype, vendorid: $vendorid, model: $model, serial: $serial, callsign: $callsign, toBow: $toBow, toStern: $toStern, toPort: $toPort, toStarboard: $toStarboard, mothershipMMSI: $mothershipMMSI}';
  }
}