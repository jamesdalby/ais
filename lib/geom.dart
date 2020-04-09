/// Navigational geometry.
import 'dart:math';

// radius of earth in NM for equirectangluar approximation
final double R = 3440;

/// Distance in nm between a & b using equirectangular approximation
double range(final double alat, final double alon, final double blat, final double blon) {
  var ar = [ rad(alat), rad(alon) ];
  var br = [ rad(blat), rad(blon) ];
  var delta = [ br[0]-ar[0], br[1]-ar[1] ];
  double x = delta[0]*cos((ar[0]+br[0])/2);
  double y = delta[1];
  return R * sqrt(x*x+y*y);
}

// degrees to radians
double rad(degrees) => degrees*pi/180;

// radians to degrees
double deg(radians) => radians*180/pi;

/// Initial bearing between a&b
double bearing(final double alat, final double alon, final double blat, final double blon) {
  var ar = [ rad(alat), rad(alon) ];
  var br = [ rad(blat), rad(blon) ];

  var y = sin(br[1] - ar[1]) * cos(br[0]);
  var x = cos(ar[0]) * sin(br[0]) -
      sin(ar[0]) * cos(br[0]) * cos(br[1] - ar[1]);
  return (360 + deg(atan2(y, x))) % 360;
}
