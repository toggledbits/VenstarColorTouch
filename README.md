# Venstar ColorTouch Thermostat Interface for Vera/MiOS #

## Introduction ##

This project is a "plug-in" for for Vera home automation controllers that mimics the behavior of a standard heating/cooling
thermostat and uses the Venstar ColorTouch API to send commands and receive status from compatible thermostats, such as the
T7850 and T7900.

VenstarColorTouch works with ALTUI, but does not work with openLuup at this time.

VenstarColorTouch is written and supported by Patrick Rigney, aka rigpapa on the [Vera forums](http://forum.micasaverde.com/).
If you find the project useful, please consider supporting my work a [small donation](https://www.toggledbits.com/donate).

## Installation ##

Installation of the plug-in is through the usual mechanisms for Vera controllers: through the Vera plugin marketplace (via
the *Apps > Install Apps* function in the Vera UI), or by downloading
the plugin files from the project's [GitHub repository](https://github.com/toggledbits/VenstarColorTouch/releases).

**Before a thermostat can be used with this plugin, the "Local API" setting must be enabled in the thermostat's menu (under Accessories).**

### Installation through Vera ###

To install the plug-in from the Vera plug-in catalog:

1. Open the Vera UI on your desktop computer;
1. Click on *Apps* in the left navigation menu;
1. Click on *Install Apps*;
1. Type "Venstar" into the search box and click "Search app";
1. Choose the "Venstar ColorTouch" app.

The plug-in will be installed, and the master (interface) device created. When the master device first runs, it will
launch SSDP (broadcast) discovery, to see if it can find any thermostats.

### Installation from GitHub ###

**Warning: this method is for experienced users only. Incorrectly uploading files to your Vera controller can cause problems, up to 
and including bricking the controller. Proceed at your own risk.**

To install from GitHub, download a release from the project's [GitHub repository](https://github.com/toggledbits/VenstarColorTouch/releases).
Unzip it, and then upload the release files to your Vera using the uploader found in the UI under Apps > Develop apps > Luup files. You should
turn off the "Restart Luup after upload" checkbox until uploading the last of the files. Turn it on for the last file.

Then, go to *Apps > Develop apps > Create device*, and enter the following data exactly as shown (copy-paste recommended), leaving all other
fields empty:

Descripion: `Venstar ColorTouch`
Upnp Device Filename: `D_VenstarColorTouchInterface1.xml`
Upnp Implementation Filename: `I_VenstarColorTouchInterface1.xml`

Then hit the *Create Device* button. Then reload Luup, and hard-refresh your browser. You should then see the master (interface) device.

## Device Discovery ##

TBD

When first installed, the VenstarColorTouch plugin will initiate network discovery and attempt to locate your compatible IntesisBox
devices. There will be several Luup reloads during this process as devices are found, and as is frequently the case in Vera, a full
refresh/cache flush of your browser will be necessary to consistently display all of the discovered devices.

The "Venstar ColorTouch" device represents the interface and controller for all of the IntesisBox devices. There is normally only
one such device, and it is the parent for all other devices created by the plugin. Clicking on the arrow in
the Vera dashboard to access the gateway's control panel will give you three options for launching network discovery. The first
will run network broadcast discovery, which is the first method you should try if the plugin did not find all of your devices. The
second option is MAC discovery, where a MAC address is entered (see the label on the IntesisBox device) and the plugin searches for
that device specifically. The third is IP discovery, which may be used if the IP address of the device is known.

Each discovered IntesisBox
device presents as a heating/cooling thermostat in the Vera UI. These devices are child devices of the parent gateway device, although
this association is not readily apparent from the UI, and in most cases is not relevant for the typical Vera user (Lua scripters will care, though).
Buttons labeled "Off", "Heat", "Cool", "Auto", "Dry" and "Fan" 
are used to change the heating/cooling unit's operating mode. The "spinner" control (up/down arrows) is used to change the setpoint temperature. 
To the right of the spinner is the current temperature as reported by the gateway. If you click the arrow in the device panel you land on the "Control" tab, and an expanded control UI is presented. The operating mode and setpoint controls are the similar, but there additional controls for fan speed and vane position.

**NOTE:** Since the IntesisBox devices are interfaces for a large number of heating/cooling units by various manufacturers, the capabilities
of each device vary considerably. For many devices, some UI buttons will have no effect, or have side-effects to other functions; 
in some cases, the buttons may affect one unit differently
from the way they affect another. This is not a defect of the plug-in, but rather the response to Intesis' interpretation of how to best control
the heating/cooling unit given its capabilities.

## Operation ##

TBD

## Actions ##

The plugin creates two device types and services:

1. Type , service `urn:toggledbits-com:serviceId:VenstarColorTouch1`, which 
1. Type , service `urn:toggledbits-com:serviceId:IntesisWMPDevice1`, which contains the state and actions associated with each IntesisBox device;

### IntesisGateway1 Service Actions and Variables ###

The IntesisGateway1 service, which must be referenced using its full name `urn:toggledbits-com:serviceId:VenstarColorTouch1`,
contains the state and actions associated with the gateway device itself. It is associated with the
`urn:schemas-toggledbits-com:device:VenstarColorTouch:1` device type.

The following actions are implemented under this service:

#### Action: RunDiscovery ####
This action launches broadcast discovery, and adds any newly-discovered compatible IntesisBox devices to the configuration.
Discovery lasts for 30 seconds, and runs asynchronously (all other tasks and jobs continue during discovery).

#### Action: DiscoverMAC ####
This action starts discovery for a given MAC address, passed in the `MACAddress` parameter. This is useful because the MAC addresses are printed on a label on the back of the
device, and if the device is connected to the same LAN as the Vera, is likely discoverable by this address. If the device is found
and compatible, it will be added to the configuration.

#### Action: DiscoverIP ####
This action starts discovery for a given IP address. If communication with the device can be established at the given address
(provided in the `IPAddreess` parameter), and the device is compatible, it will be added to the configuration.

#### Action: SetDebug ####
This action enables debugging to the Vera log, which increases the verbosity of the plugins information output. It takes a single
parameter, `debug`, which must be either 0 or 1 in numeric or string form.

### Variable: RefreshInterval ###

`RefreshInterval` is the time between full queries for data from the gateway. Periodically, the plug-in will make a query for all current
gateway status parameters, to ensure that the Vera plug-in and UI are in sync with the gateway. This value is in seconds, and the default
is 60. It is not recommended to set this value lower than the ping interval (above).

### Other Services ###

In addition to the above services, the VenstarColorTouch plug-in implements the following "standard" services for thermostats (IntesisDevice1 devices):

* `urn:upnp-org:serviceId:HVAC_UserOperatingMode1`: `SetModeTarget` (Off, AutoChangeOver, HeatOn, CoolOn), `GetModeTarget`, `GetModeStatus`
* `urn:upnp-org:serviceId:HVAC_FanOperatingMode1`: `SetMode` (Auto, ContinuousOn), `GetMode`
* `urn:upnp-org:serviceId:TemperatureSetpoint1`: `SetCurrentSetpoint`, `GetCurrentSetpoint`

The plug-in also provides many of the state variables behind these services. In addition, the plug-in maintains the `CurrentTemperature` 
state variable of the `urn:upnp-org:serviceId:TemperatureSensor1` service (current ambient temperature as reported by the gateway).

**IMPORTANT:** The model for handling fan mode differs significantly between Intesis and Vera. In Vera/UPnP, setting the fan mode to `ContinuousOn`
turns the fan on, but does not change the operating mode of the air handling unit. For example, with the fan mode set to ContinuousOn,
if the AHU is cooling, it continues to cool until setpoint is achieved, at which time cooling shuts down but the fan continues to operate.
In Intesis, to get continuous operation of the fan, one sets the (operating) mode to "Fan", which will stop the AHU from heating or cooling.
Because of this, the plugin does not react to the `SetMode` action in service `urn:upnp-org:serviceId:HVAC_FanOperatingMode1` 
(it is quietly ignored).
In addition, the `FanStatus` state can only be deduced in the "Off" or "FanOnly" operating modes, in which case the status will
be "Off" or "On" respectively; in all other cases it will be "Unknown".

**IMPORTANT:** Also note that I take a different view of `ModeTarget` and `ModeStatus` (in HVAC_UserOperatingMode1) from Vera. Vera mostly
(although not consistently) sees the two as nearly equivalent, with the latter (ModeStatus) following ModeTarget. That is, if ModeTarget
is set to "HeatOn", ModeStatus also becomes "HeatOn". This is not entirely in keeping with UPnP in my opinion. UPnP says, in essence, that
ModeTarget is the desired operating mode, and ModeStatus is the current operating state. This may sound like the same thing, except that
UPnP takes status much more temporally than Vera; that is, UPnP says if ModeTarget is "HeatOn", but there is no call for heat because the
temperature is within the setpoint hysteresis (aka the "deadband"), then ModeStatus may be "InDeadBand", indicating that the unit is currently
not doing anything. When the current temperature
deviates too far from the setpoint and the call for heat comes, then ModeStatus goes to "HeatOn", indicating that the air handling unit is
then providing heat. In other words, Vera says ModeStatus is effectively a confirmation of ModeTarget, while
UPnP says that ModeTarget is the goal, and ModeStatus reflects the at-the-moment state of the unit's activity toward the goal. 
Vera, then, has had to introduce a new non-standard variable (ModeState) to communicate what could and should be communicated in the service-standard variable.

### IntesisERRSTATUS and IntesisERRCODE ###

The plugin will store the values of any ERRSTATUS and ERRCODE reports from the gateway device. Because the meaning of these codes varies from device to device, the plugin does not act on them, but since they are stored, user-provided scripts could interpret the values and react using specific knowledge of the air handling unit installed.

## ImperiHome Integration ##

ImperiHome does not, by default, detect many plugin devices, including ImperiHome WMP Gateway. However, it is possible to configure this plugin
for use with ImperiHome, as the plugin implements the [ImperiHome ISS API](http://dev.evertygo.com/api/iss).

To connect to ImperiHome:

1. In ImperiHome, go into **My Objects**
1. Click **Add a new object**
1. Choose **ImperiHome Standard System**
1. In the **Local base API** field, enter 
   `http://your-vera-local-ip/port_3480/data_request?id=lr_VenstarColorTouch&command=ISS`
1. Click **Next** to connect.

ImperiHome should then populate your groups with your Venstar ColorTouch plugin devices.

## Reporting Bugs/Enhancement Requests ##

Bug reports and enhancement requests are welcome! Please use the ["Issues" section](https://github.com/toggledbits/VenstarColorTouch/issues) of the Github repository to open a new bug report or make an enhancement request.

## License ##

VenstarColorTouch is offered under GPL (the GNU Public License) 3.0. See the [LICENSE](https://www.gnu.org/licenses/gpl-3.0.en.html) file for details.

<hr>Copyright 2017,2018 Patrick H. Rigney, All Rights Reserved
