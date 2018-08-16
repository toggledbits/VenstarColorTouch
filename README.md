# Venstar ColorTouch Thermostat Interface for Vera/MiOS #

## Introduction ##

This project is a "plug-in" for for Vera home automation controllers that present the UI of a standard dual heating/cooling
thermostat and uses the Venstar ColorTouch API to send commands to and receive status from compatible thermostats, such as the
Venstar T7850 and T7900.

This plugin works with ALTUI, but does not work with openLuup at this time.

The plugin is written and supported by Patrick Rigney, aka rigpapa on the [Vera forums](http://forum.micasaverde.com/).
If you find the project useful, please consider supporting my work with a [small donation](https://www.toggledbits.com/donate).

## Installation ##

### Configuring Your Venstar Thermostat ###

**IMPORTANT!** Be sure to perform these configuration steps before installing the plugin. It will make your life easier.

The following must be configured on your thermostat:

1. Go to the "Wi-Fi Status" page (under the "Wi-Fi" menu), and confirm that you are connected to the network and have good signal strength--if not, configure or troubleshoot that before continuing (see your thermostat's documentation);
1. Write down the MAC and IP addresses shown on the "Wi-Fi Status" page;
1. Under the "Wi-Fi" menu, turn on the "Local API";
1. Under the "Wi-Fi" menu, the "API Protocol" must be set to "http" (HTTPS is not yet supported);
1. The "Basic Auth" settings must both be blank/empty (the plugin currently does not support HTTP Basic Authentication).

Once you have completed this configuration, confirm that your thermostat's API is reachable by opening the thermostat in a browser. For example, if your thermostat's assigned IP (from step 2) is 192.168.9.100, then you would open `http://192.168.9.100/`. You should get a short JSON response containing the string "api_ver" (it does not matter what version of the API your thermostat uses).

### Installation from Vera Plugin Marketplace ###

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
Unzip it, and then upload the release files to your Vera using the uploader found in the UI under *Apps > Develop apps > Luup files*. You should
turn off the "Restart Luup after upload" checkbox until uploading the last of the files. Turn it on for the last file.

Next, go to *Apps > Develop apps > Create device*, and enter the following data exactly as shown (copy-paste recommended), leaving all other
fields empty:

* Descripion: `Venstar ColorTouch`
* Upnp Device Filename: `D_VenstarColorTouchInterface1.xml`
* Upnp Implementation Filename: `I_VenstarColorTouchInterface1.xml`

Then hit the *Create Device* button. Then reload Luup, and hard-refresh your browser. You should then see the master (interface) device.

Note: you can also follow the latest development updates by periodically downloading the "stable" branch from the Github repository, and uploading
those files to your Vera. Uploading files from the "develop" branch is not recommended.

## Device Discovery ##

**The ability of the plugin to discover your thermostats, or really function at all, requires that you first successfully complete the steps in 
*Configuring Your Venstar Thermostat*, above, and confirm your thermostat's API is reachable.**

When first installed, the Venstar ColorTouch plugin will initiate SSDP discovery and attempt to locate your compatible thermostats. There will be a couple of Luup reloads during this process as devices are found, and as is frequently the case in Vera, a full refresh/cache flush of your browser will be necessary to consistently display all of the discovered devices.

The performance of SSDP discovery has varied a bit between versions of Vera firmware. If your installation doesn't discover any thermostats, don't panic! There are two alternatives: MAC discovery, and IP discovery.

For MAC discovery, you will need to know the MAC address of the device (from step 2 of *Configuring Your Venstar Thermostat*, above). To start MAC discovery, go into the interface device's control panel, and enter the MAC address in the field next to the "Discover MAC" button. Then press that button. If the device can be found by its MAC address, you'll see a message to that effect, and Luup will reload. Make sure to do a hard-reload of your browser before proceeding.

If MAC discovery fails, the final option is IP discovery. You will need to know the current IP address of the device (which you should have from step 2 of *Configuring Your Venstar Thermostat*, above). Enter the IP address in the field next to the "Discover IP" button. If you have configured the "API Protocol" in the thermostat settings for HTTPS, add ":443" to the end of the IP address. Then press the "Discover IP" button. If the thermostat can be contacted on that IP address, the plugin will configure it.

Repeat these discovery steps for each thermostat. It is recommended that you always start with broadcast (SSDP) discovery, as this gives the plugin important configuration information up front. When it works, it gives the best result.

## Operation ##

The plugin implements the interface a standard dual heating/cooling auto-changeover thermostat. It will restrict functions to those which the thermostat advertises as available, so, for example, if the connected thermostat cannot do auto-changeover mode, that option will not operate on the interface (it will still be shown).

The plugin also enforces limits on the range and separation of the heating and cooling setpoints. These are determined by the thermostat. For example, if the cooling setpoint is 74F, and the thermostat requires a minimum separation of two degrees between setpoints, setting the heating setpoint to 73F will cause the cooling setpoint to be moved up to 75F.

## Actions ##

### Interface Service Actions and Variables ###

The interface service, which must be referenced using its full name `urn:toggledbits-com:serviceId:VenstarColorTouchInterface1`,
contains the state and actions associated with the interface device itself. It is associated with the
`urn:schemas-toggledbits-com:device:VenstarColorTouchInterface:1` device type.

The following actions are implemented under this service:

#### Action: RunDiscovery ####
This action launches broadcast (SSDP) discovery, and adds any newly-discovered compatible IntesisBox devices to the configuration.
Discovery lasts for 30 seconds, and runs asynchronously (all other tasks and jobs continue during discovery).

#### Action: DiscoverMAC ####
This action starts discovery for a given MAC address, passed in the `MACAddress` parameter. This is useful because the MAC addresses are printed on a label on the back of the
device, and if the device is connected to the same LAN as the Vera, is likely discoverable by this address. If the device is found
and compatible, it will be added to the configuration.

#### Action: DiscoverIP ####
This action starts discovery for a given IP address. If communication with the device can be established at the given address
(provided in the `IPAddreess` parameter), and the device is compatible, it will be added to the configuration. The IP address given may contain an optional ":port" suffix, to specify the port on which the API for the target device operates (default is port 80, the standard HTTP port).

#### Action: SetDebug ####
This action enables debugging to the Vera log, which increases the verbosity of the plugins information output. It takes a single
parameter, `debug`, which must be either 0 or 1 in numeric or string form.

### State Variable: RefreshInterval ###

`RefreshInterval` is the time between full queries for data from the gateway. Periodically, the plug-in will make a query for all current
gateway status parameters, to ensure that the Vera plug-in and UI are in sync with the gateway. This value is in seconds, and the default
is 60. Setting this value too low may cause excessive network traffic and higher Vera CPU loads.

### Other Services ###

In addition to the above services, the VenstarColorTouch plug-in implements the following "standard" services for thermostats (VenstarColorTouchThermostat1 devices):

* `urn:upnp-org:serviceId:HVAC_UserOperatingMode1`: `SetModeTarget` (Off, AutoChangeOver, HeatOn, CoolOn), `GetModeTarget`, `GetModeStatus`
* `urn:upnp-org:serviceId:HVAC_FanOperatingMode1`: `SetMode` (Auto, ContinuousOn), `GetMode`
* `urn:upnp-org:serviceId:TemperatureSetpoint1`: `SetApplication`, `SetCurrentSetpoint`, `GetCurrentSetpoint` (UPnP standard)
* `urn:upnp-org:serviceId:TemperatureSetpoint1_Heat` and `_Cool`: `SetCurrentSetpoint`, `GetCurrentSetpoint` (Vera's version of UPnP)

The `SetCurrentSetpoint` action function a bit differently from UPnP, and this is a Vera-ism. When the action is called with the `urn:upnp-org:serviceId:TemperatureSetpoint1_Heat`
service, the heating setpoint is changed, and when called with the `urn:upnp-org:serviceId:TemperatureSetpoint1_Cool` service, the cooling setpoint is changed. It is also possible to use the UPnP `SetApplication` and `SetCurrentSetpoint` method in the standard `urn:upnp-org:serviceId:TemperatureSetpoint1` service. An enhancement for this plugin is that the new setpoint can be specified with units (e.g. "15C" or "72F"), to allow a setpoint to be set in units other than that which the thermostat is configured to display.

The plug-in also provides many of the common state variables behind these services. In addition, the plug-in maintains the `CurrentTemperature` 
state variable of the `urn:upnp-org:serviceId:TemperatureSensor1` service (current ambient temperature as reported by the gateway). If humidity information is returned by the thermostat, the `CurrentLevel` state variable of the `urn:micasaverde-com:serviceId:HumiditySensor1` service is also available.

## Vera Android and iOS Applications ##

Due to limitations of the Vera mobile apps, most plugin devices do not appear in those apps, and this plugin is no exception. This limitation should be familiar to most Vera users.

## ImperiHome Integration ##

Like the Vera mobile apps, ImperiHome does not, by default, detect many plugin devices, including this one. However, it is possible to configure this plugin
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

Support questions, bug reports and enhancement requests are welcome! There are two ways to share them:

1. Use the [official Venstar ColorTouch plugin thread in the Vera forums](http://);
1. Use the ["Issues" section](https://github.com/toggledbits/VenstarColorTouch/issues) of the Github repository.

## License ##

VenstarColorTouch is offered under GPL (the GNU Public License) 3.0. See the [LICENSE](https://www.gnu.org/licenses/gpl-3.0.en.html) file for details.

<hr>Copyright 2017,2018 Patrick H. Rigney, All Rights Reserved
