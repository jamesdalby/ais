import 'aisdecode.dart';
import 'cpa.dart';
import 'package:nmea/nmea.dart';

/// Core AIS handler class used to connect to an NMEA0183 source and
/// decode messages therefrom.
///
/// Override `we(PCS)` and `they(PCS us, PCS them, int mmsi)`
/// to implement your own AIS handler.
///
/// `we(PCS)` will be invoked any time an incoming position record (RMC) is received
///
/// `they(us, them, mmsi)` will be invoked any time a (complete) VDM sentence is received.
///
/// This will attempt to reconnect if a connection is dropped see [NMEASocketReader] for details.
///
/// This class maintains a (non-persistent) cache of the most recent message of each type received, keyed by MMSI
/// useful for doing things like name lookup and drilldown to full AIS data should you need to.
abstract class AISHandler {
  String? _lastMsg;
  String _payload = '';

  final NMEAReader _nmea;

  /// Create a handler reading from host:port
  AISHandler(String host, int port) : _nmea = NMEASocketReader(host, port);
  AISHandler.using(this._nmea);

  // switch source/restart??


  // Start running
  void run() => _nmea.process(_handleNMEA);

  /// Change the host and port number; will disconnect and reconnect to a new source.
  void setSource(final String host, final int port) {
    if (_nmea is NMEASocketReader) {
      (_nmea as NMEASocketReader).hostname = host;
      (_nmea as NMEASocketReader).port = port;
    }
  }

  // The underlying NMEA reader
  NMEAReader get nmea => _nmea;

  /// [we] will be invoked each time a position record (RMC) is received on the NMEA bus
  void we(final PCS us);

  /// [they] will be invoked each time an AIS target is reported
  ///
  /// [us] is the [PCS] for our boat
  ///
  /// [them] is the [PCS] of the target
  ///
  /// [mmsi] is the MMSI of the target.
  void they(final PCS us, final PCS them, final int mmsi);

  // most recently received position
  PCS? _us;

  // Map of MMSI to ship name
  // Map<int,String> _names = {};

  // Map of MMSI to Type to most recently received VDM
  Map<int,Map<int,AIS>> _static = Map();

  /// Ship name of given mmsi or null if unknown.
  ///
  /// This is derived from Type5 and Type24 messages, and is not persistent
  /// int this basic implementation, so you will only get non-null if a message of that
  /// type has already been received during the current lifecycle of this class.
  // String name(final int mmsi) => _names[mmsi];

  /// Invoked when a message arrives that associates MMSI with a name
  /// Useful to override if you want to track this (e.g to provide persistence capability)
  // @mustCallSuper
  // void set(final int mmsi, String name) => _names[mmsi] = name;

  /// Most recent message of given [type] from [mmsi]
  ///
  /// If no message has been received, or this MMSI is unknown, then returns null
  AIS? getMostRecentMessage(final int mmsi, final int msgType) => _static[mmsi]?[msgType];

  // Most recent messages of each type for given mmsi
  Map<int, AIS>? getMostRecentMessages(final int mmsi) {
    var m = _static[mmsi];
    return m == null ? null : Map.unmodifiable(m);
  }

  // stash the message by MMSI and Type
  void _stash(final int? mmsi, final int type, final AIS ais) {
    if (mmsi==null) return;

    _static.putIfAbsent(mmsi, ()=>new Map<int,AIS>())[type] = ais;
  }

  // receiver for NMEA messges
  void _handleNMEA(var msg) {
    if (msg is RMC) {
      _us = PCS(msg.position.lat, msg.position.lng, msg.trackMadeGood, msg.sog);
      // print('   '+_us.toString());
      we(_us!);
    }
    if (msg is Pos) {
      // Consider caching pos & course & speed,and then invoking us on these?  RMC is probably the exact same thing, I suspect.
      // print(msg.runtimeType.toString() +' '+ dms(msg.lat*60, 'N','S',null, 4) +' '+ dms(msg.lng*60, 'E','W',null,4) );
    }
    if (msg is VTG) {
      // print("vtg");
    }

    // Here's the meat:
    if (msg is VDM) {
      // NMEA process has already unpacked the message; the interesting bit is in [payload].
      // Accumulate the payload until [fragment] == [fragments]
      // as VDMs can span multiple NMEA sentences
      _payload += msg.payload;
      if (msg.fragment == msg.fragments) {
        // this is the last message in the chain
        final AIS ais = AIS.from(_payload);

        if (ais is Type5) {
          nameFor(ais.mmsi, ais.shipname);
          _stash(ais.mmsi, 5, ais);

        } else if (ais is Type24A) {
          nameFor(ais.mmsi, ais.shipname);
          _stash(ais.mmsi, 0x24A, ais);

        } else if (ais is Type18) {
          _stash(ais.mmsi, 0x18, ais);
          if (_us != null) {
            if (ais.course != null && ais.lat != null && ais.lon != null) {
              PCS them = PCS(ais.lat / 60, ais.lon / 60, ais.course, ais.speed);
              they(_us!, them, ais.mmsi);
            }
          }

        } else if (ais is CNB) {
          _stash(ais.mmsi, ais.type, ais);
          // Type 1, 2, 3 extend CNB:
          if (_us != null) {
            if (ais.course != null && ais.lat != null && ais.lon != null) {
              PCS them = PCS(ais.lat / 60, ais.lon / 60, ais.course, ais.sog);
              they(_us!, them, ais.mmsi);
            }
          }
        } else if (ais is Type24B) {
          _stash(ais.mmsi, 0x24B, ais);
          // do something else?

        } else if (ais is Type21) {
          // static stuff: buoys, lanbys etc
          nameFor(ais.mmsi, ais.name);
          _stash(ais.mmsi, 21, ais);
          // _names[ais.mmsi] = ais.name;
          if (_us != null) {
            if (ais.lat != null && ais.lon != null) {
              PCS them = PCS(ais.lat / 60, ais.lon / 60, 0, 0);
              they(_us!, them, ais.mmsi);
            }
          }

        } else {
          // print("not handled: $ais");

        }

        _lastMsg = null;
        _payload = '';
      } else if (_lastMsg != null && _lastMsg != msg.msgID) {
        // unexpected - out of sequence?

      } else {
        _lastMsg = msg.msgID;
      }
    }
  }

  /// Override this method if you want to be advised of name updates.
  void nameFor(int? mmsi, String? shipname) {}
}