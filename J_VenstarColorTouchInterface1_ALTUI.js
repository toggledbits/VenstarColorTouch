//# sourceURL=J_VenstarColorTouchInterface1_ALTUI.js
"use strict";

var VenstarColorTouchInterface1_ALTUI = ( function( window, undefined ) {

        function _draw( device ) {
                var html ="";
                var s = MultiBox.getStatus( device, "urn:toggledbits-com:serviceId:VenstarColorTouchInterface1", "DisplayStatus");
                html += '<div>' + s + '</div>';
                return html;
        }
    return {
        DeviceDraw: _draw,
    };
})( window );
