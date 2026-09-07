import QtQuick 2.6
import QtGraphicalEffects 1.0

// Approximates a Lovelace state_filter. Cards load this through a Loader so a
// device without QtGraphicalEffects still shows the untinted picture.
HueSaturation {
    property real filterHue: 0
    property real filterSaturation: 0
    property real filterLightness: 0

    hue: filterHue
    saturation: filterSaturation
    lightness: filterLightness
}
