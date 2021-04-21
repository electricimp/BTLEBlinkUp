// MIT License
//
// Copyright (c) 2021 Twilio.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.


/**
 * @constant {integer} BTLE_BLINKUP_WIFI_SCAN_INTERVAL - The interval between separate WiFi network scans.
 *
*/
const BTLE_BLINKUP_WIFI_SCAN_INTERVAL = 120;

/**
 * @constant {integer} BTLE_BLINKUP_MIN_IMPOS - The minimum version of impOS supported.
 *
*/
const BTLE_BLINKUP_MIN_IMPOS = 41.28;

/**
 * Squirrel class for providing BlinkUp services via Bluetooth LE on a compatible imp.
 *
 * Bus          UART
 * Availibility Device
 * @author      Tony Smith (@smittytone)
 * @license     MIT
 *
 * @class
*/
class BTLEBlinkUp {

    /**
     * @property {string} VERSION - The library version.
     *
    */
    static VERSION = "2.1.0";

    /**
     * @property {imp::bluetooth} ble - The imp API hardware.bluetooth instance.
     *
    */
    ble = null;

    /**
     * @property {string} agentURL - The URL of the device's agent.
     *
    */
    agentURL = null;

    // ********** Private instance properties **********
    _uuids = null;
    _blinkup = null;
    _incoming = null;
    _incomingCB = null;
    _networks = null;
    _pin_LPO_IN = null;
    _pin_BT_REG_ON = null;
    _uart = null;
    _blinking = false;
    _scanning = false;
    _impType = null;
    _version = null;

    /**
     * Instantiate the BLE BlinkUp Class.
     * NOTE lpoPin, regonPin and uart only required by imp004m.
     *
     * @constructor
     *
     * @param {array}     uuids      - Table of UUID service values (see Read Me).
     * @param {string}    [firmware] - The Bluetooth radio firmware. Not required on imp006 with 41.24 and up
     * @param {imp::pin}  [lpoPin]   - The imp004m module pin object connected to the BLE modele's LPO pin. Default: hardware.pinE.
     * @param {imp::pin}  [regonPin] - The imp004m module pin object connected to the BLE modele's REG_ON pin. Default: hardware.pinJ.
     * @param {imp::uart} [uart]     - The configured imp004m UART bus to which the BLE module is connected. Default: hardware.uartFGJH.
     *
     * @returns {instance} The instance.
     *
     */
    constructor(uuids = null, firmware = null, lpoPin = null, regonPin = null, uart = null) {
        // Determine the imp we're running on
        _impType = imp.info().type;

        if (_impType == "imp004m") {
            // Set the BLE radio pins, either to the passed in values, or the defaults
            // Defaults to the imp004m Breakout Board
            _pin_LPO_IN = lpoPin != null ? lpoPin : hardware.pinE;
            _pin_BT_REG_ON = regonPin != null ? regonPin : hardware.pinJ;
            _uart = uart != null ? uart : hardware.uartFGJH;

            // Check that we have recieved firmware
            if (firmware == null) throw "BTLEBlinkUp() requires Bluetooth firmware supplied as a string or blob for imp004m.";
        } else if (_impType == "imp006"){
            // FROM 2.1.0 -- check we're running on the right impOS for imp006
            try {
                local version = imp.getsoftwareversion();
                local pos = version.find("release");
                _version = version.slice(pos + 8, pos + 13).tofloat();

                // No firmware? Thow on impOS less than min.
                if (firmware == null && _version < BTLE_BLINKUP_MIN_IMPOS) throw format("BTLEBlinkUp() requires Bluetooth firmware supplied as a string or blob for imp006 on impOS under %.2f", BTLE_BLINKUP_MIN_IMPOS);
            } catch (err) {
                throw err;
            }
        } else {
            throw "BTLEBlinkUp() supports imp004m or imp006";
        }

        // Apply the BlinkUp service's UUIDs, or the defaults if none are provided
        if (uuids == null || typeof uuids != "table" || uuids.len() != 8) throw "BTLEBlinkUp() requires service UUIDs to be provided as a table";
        if (!_checkUUIDs(uuids)) throw "BTLEBlinkUp() requires the service UUID table to contain specific key names";
        _uuids = uuids;

        // Initialize the radio
        _init(firmware);
    }

    /**
     * Listen for a BlinkUp request.
     *
     * This is a convenience method for serving BlinkUp. It assumes that you have already specified the required level of security,
     * using setSecurity(). It uses default values for advertising, min. and max. interval values, and serves only the BlinkUp
     * and Device Information services.
     *
     * @param {string|blob} [advert]   - Optional BLE advertisement. Default: library-set advert.
     * @param {function}    [callback] - Optional 'on connected' callback function. Default: null.
     *
     */
    function listenForBlinkUp(advert = null, callback = null) {
        serve();
        onConnect(callback);
        advertise(advert);
    }

    /**
     * Set Bluetooth LE security mode.
     *
     * Specify the Bluetooth LE security mode (and PIN) as per the imp API method bluetooth.setsecurity().
     * It will default to no security (mode 1) in case of error.
     * NOTE This needs to be run separately from listenForBlinkUp().
     *
     * @param {integer}        mode  - BLE security mode integer: 1, 3 or 4.
     * @param {string|integer} [pin] - Optional 'on connected' callback function. Default: "000000".
     *
     * @returns {integer} The mode selected.
     *
     */
    function setSecurity(mode = 1, pin = "000000") {
        // Check for a valid Bluetooth instance
        if (ble == null) {
            server.error("BTLEBlinkUp.setSecurity() - Bluetooth LE not initialized");
            return 1;
        }

        // Check that a valid mode has been provided
        if (mode != 1 && mode != 3 && mode != 4) {
            server.error("BTLEBlinkUp.setSecurity() - undefined security mode selected");
            ble.setsecurity(1);
            return 1;
        }

        // Check that a PIN has been provided for modes 3 and 4
        if (pin == null && mode > 1) {
            server.error("BTLEBlinkUp.setSecurity() - security modes 3 and 4 require a PIN");
            ble.setsecurity(1);
            return 1;
        }

        // Parameter 'pin' should be a string or an integer and no more than six digits
        if (typeof pin == "string") {
            if (pin.len() > 6) {
                server.error("BTLEBlinkUp.setSecurity() - security PIN cannot be more than six characters");
                ble.setsecurity(1);
                return 1;
            }

            try {
                pin = pin.tointeger();
            } catch (err) {
                server.error("BTLEBlinkUp.setSecurity() - security PIN must contain only decimal numeric characters");
                ble.setsecurity(1);
                return 1;
            }
        } else if (typeof pin == "integer") {
            if (pin < 0 || pin > 999999) {
                server.error("BTLEBlinkUp.setSecurity() - security PIN must contain 1 to 6 digits");
                ble.setsecurity(1);
                return 1;
            }
        } else {
            server.error("BTLEBlinkUp.setSecurity() - security PIN must be a string or integer");
            ble.setsecurity(1);
            return 1;
        }

        if (mode == 1) {
            // Ignore the pin as it's not needed
            ble.setsecurity(1);
        } else {
            ble.setsecurity(mode, pin);
        }

        return mode;
    }

    /**
     * Set the Agent URL of the host device.
     *
     * This is included in the device info service data.
     *
     * @param {string} url  - The agent's URL string.
     *
     * @returns {string} The specified URL. Will be an empty string if the agent URL could not be set.
     *
     */
    function setAgentURL(url = "") {
        agentURL = typeof url == "string" ? url : "";
        return agentURL;
    }

    /**
     * Set up the Bluetooth GATT server for BlinkUp.
     *
     * This always adds the BlinkUp service and standard Device Info service.
     *
     * @param {array} [otherServices] - An array of one or more services which you would like the device to
     *                                  provides **in addition** to BlinkUp and the standard Device Info service.
     *
     */
    function serve(otherServices = null) {
        // Check for a valid Bluetooth instance
        if (ble == null) {
            server.error("BTLEBlinkUp.serve() - Bluetooth LE not initialized");
            return;
        }

        // Define the BlinkUp service
        local service = {};
        service.uuid <- _uuids.blinkup_service_uuid;
        service.chars <- [];

        // Define the SSID setter characteristic
        local chrx = {};
        chrx.uuid <- _uuids.ssid_setter_uuid;
        chrx.flags <- 0x08;
        chrx.write <- function(conn, v) {
            _blinkup.ssid = v.tostring();
            _blinkup.updated = true;
            server.log("WiFi SSID set");
            return 0x0000;
        }.bindenv(this);
        service.chars.append(chrx);

        // Define the password setter characteristic
        chrx = {};
        chrx.uuid <- _uuids.password_setter_uuid;
        chrx.write <- function(conn, v) {
            _blinkup.pwd = v.tostring();
            _blinkup.updated = true;
            server.log("WiFi password set");
            return 0x0000;
        }.bindenv(this);
        service.chars.append(chrx);

        // Define the Plan ID setter characteristic
        chrx = {};
        chrx.uuid <- _uuids.planid_setter_uuid;
        chrx.write <- function(conn, v) {
            _blinkup.planid = v.tostring();
            _blinkup.updated = true;
            server.log("Plan ID set");
            return 0x0000;
        }.bindenv(this);
        service.chars.append(chrx);

        // Define the Enrollment Token setter characteristic
        chrx = {};
        chrx.uuid <- _uuids.token_setter_uuid;
        chrx.write <- function(conn, v) {
            _blinkup.token = v.tostring();
            _blinkup.updated = true;
            server.log("Enrolment Token set");
            return 0x0000;
        }.bindenv(this);
        service.chars.append(chrx);

        // Define a dummy setter characteristic to trigger the imp restart
        chrx = {};
        chrx.uuid <- _uuids.blinkup_trigger_uuid;
        chrx.write <- function(conn, v) {
            if (_blinkup.updated) {
                server.log("Device Activation triggered");
                _blinkup.update();
                return 0x0000;
            } else {
                return 0x1000;
            }
        }.bindenv(this);
        service.chars.append(chrx);

        // Define a dummy setter characteristic to trigger WiFi clearance
        chrx = {};
        chrx.uuid <- _uuids.wifi_clear_trigger_uuid;
        chrx.write <- function(conn, v) {
            server.log("Device WiFi clearance triggered");
            _blinkup.clear();
            return 0x0000;
        }.bindenv(this);
        service.chars.append(chrx);

        // Define the getter characteristic that serves the list of nearby WLANs
        chrx = {};
        chrx.uuid <- _uuids.wifi_getter_uuid;
        chrx.read <- function(conn) {
            // There's no http.jsonencode() on the device so stringify the key data
            // Networks are stored as "ssid[newline]open/secure[newline][newline]"
            // NOTE set _blinking to true so we don't asynchronously update the list
            //      of networks while also using it here
            server.log("Sending WLAN list to app");
            local ns = "";
            _blinking = true;
            for (local i = 0 ; i < _networks.len() ; i++) {
                local network = _networks[i];
                ns += (network["ssid"] + "\n");
                ns += ((network["open"] ? "unlocked" : "locked") + "\n\n");
            }
            _blinking = false;

            // Remove the final two newlines
            ns = ns.slice(0, ns.len() - 2);
            return ns;
        }.bindenv(this);
        service.chars.append(chrx);

        // Offer the service we have just defined
        local services = [];
        services.append(service);

        // Device information service
        service = { "uuid": 0x180A,
                    "chars": [
                      { "uuid": 0x2A29, "value": "Electric Imp" },           // manufacturer name
                      { "uuid": 0x2A25, "value": hardware.getdeviceid() },   // serial number
                      { "uuid": 0x2A24, "value": imp.info().type },          // model number
                      { "uuid": 0x2A23, "value": (agentURL != null ? agentURL : "null") },   // system ID (agent ID)
                      { "uuid": 0x2A26, "value": imp.getsoftwareversion() }] // firmware version
                    };

        services.append(service);
        if (otherServices != null) {
            if (typeof otherServices == "array") {
                services.extend(otherServices);
            } else if (typeof otherServices == "table") {
                services.append(otherServices);
            }
        }
        ble.servegatt(services);
    }

    /**
     * Begin advertising the device.
     *
     * NOTE If no argument is passed in to 'advert', the library will build one of its own based on the BlinkUp service,
     *      but this will leave the device unnamed.
     *
     * @param {blob|string} advert - A BLE advertisement packet. Must be 31 bytes or less. We do not check that the data is valid.
     * @param {integer}     [max]  - Optional maximum interval in ms. Default: 100.
     * @param {integer}     [min]  - Optional minimum interval in ms. Default: 100.
     *
     */
    function advertise(advert = null, min = 100, max = 100) {
        // Check for a valid Bluetooth instance
        if (ble == null) {
            server.error("BTLEBlinkUp.advertise() - Bluetooth LE not initialized");
            return;
        }

        // Check the 'min' and 'max' values
        if (min < 0 || min > 100) min = 100;
        if (max < 0 || max > 100) max = 100;
        if (min > max) {
          // Swap 'min' and 'max' around if 'min' is bigger than 'max'
          local a = max;
          max = min;
          min = a;
        }

        // Advertise the supplied advert then exit
        if (advert != null) {
            if (typeof advert != "blob" && typeof advert != "string") {
                server.error("BTLEBlinkUp.advertise() - Misformed advertisement provided");
                return;
            }

            if (advert.len() > 31) {
                server.error("BTLEBlinkUp.advertise() - Advertisement data too long (31 bytes max.)");
                return;
            }

            ble.startadvertise(advert, min, max);
            return;
        }

        // Otherwise build the advert packed based on the service UUID
        // NOTE We need to reverse the octet order for transmission
        local ss = _uuids.blinkup_service_uuid;
        local ns = imp.info().type;
        local ab = blob(ss.len() / 2 + ns.len() + 4);
        ab.seek(0, 'b');

        // Write in the BlinkUp service UUID:
        // Byte 0 - The data length
        ab.writen(ss.len() / 2 + 1, 'b');
        // Byte 1 - The data type flag (0x07)
        ab.writen(7, 'b');
        // Bytes 2+ — The UUID in little endian
        local maxs = ss.len() - 2;
        for (local i = 0 ; i < maxs + 2 ; i += 2) {
            local bs = ss.slice(maxs - i, maxs - i + 2)
            ab.writen(_hexStringToInt(bs), 'b');
        }

        // Write in the device name
        // Byte 0 - The length
        ab.writen(ns.len() + 1, 'b');
        // Byte 1 - The data type flag (0x09)
        ab.writen(9, 'b');
        // Bytes 2+ - The imp type as its name
        foreach (ch in ns) ab.writen(ch, 'b');

        ble.startadvertise(ab, min, max);
    }

    /**
     * The onConnect callback
     *
     * @callback onConnect
     *
     * @param {imp::bluetoothconnection} conn     - The connection's imp API BluetoothConnection instance.
     * @param {string}                   address  - The connection's address.
     * @param {integer}                  security - The security mode of the connection (1, 3 or 4).
     * @param {string}                   state    - The state of the connection: "connnected" or "disconnected".
     *
     */

    /**
     * Register the host app's connection/disconnection notification callback.
     *
     * NOTE If no argument is passed in to 'advert', the library will build one of its own based on the BlinkUp service,
     *      but this will leave the device unnamed.
     *
     * @param {onConnect} callback - A function in the host app to handle connection events.
     *
     */
    function onConnect(callback = null) {
        // Check for a valid Bluetooth instance
        if (ble == null) {
            server.error("BTLEBlinkUp.onConnect() - Bluetooth LE not initialized");
            return;
        }

        // Check for a valid connection/disconnection notification callback
        if (callback == null || typeof callback != "function") {
            server.error("BTLEBlinkUp.onConnect() requires a non-null callback");
            return;
        }

        // Store the host app's callback...
        _incomingCB = callback;

        // ...which will be triggered by the library's own
        // connection callback, _connectHandler()
        ble.onconnect(_connectHandler.bindenv(this));
    }

    // ********** PRIVATE FUNCTIONS - DO NOT CALL **********

    /**
     * Boot up the Bluetooth radio: set up the power lines via GPIO.
     *
     * @private
     *
     */
    function _init(firmware) {
        // FROM 2.0.0, support imp006 by partitioning imp004m-specific settings
        if (_impType == "imp004m") {
            // NOTE These require a suitably connected module - we can't check for that here
            _pin_LPO_IN.configure(DIGITAL_OUT, 0);
            _pin_BT_REG_ON.configure(DIGITAL_OUT, 1);
        }

        // Scan for WiFi networks around the device
        local now = hardware.millis();
        _scan(false);

        // Set up the incoming data structure which includes a function to trigger
        // that handles the application of the received data
        _blinkup = {};
        _blinkup.ssid <- "";
        _blinkup.pwd <- "";
        _blinkup.planid <- "";
        _blinkup.token <- "";
        _blinkup.updated <- false;
        _blinkup.update <- function() {
            // Apply the received data
            // TODO check for errors
            // Close the existing connection to the mobile app
            if (_incoming != null) _incoming.close();
            _blinking = true;

            // Disconnect from the server
            server.flush(10);
            server.disconnect();

            // Apply the new WiFi details
            imp.setwificonfiguration(_blinkup.ssid, _blinkup.pwd);

            if (_blinkup.planid != "" && _blinkup.token != "") {
                // Only write the plan ID and enrollment token if they have been set
                // NOTE This is to support WiFi-only BlinkUp
                imp.setenroltokens(_blinkup.planid, _blinkup.token);
            }

            // Inform the host app about activation - it may use this, eg. to
            // write a 'has activated' signature to the SPI flash
            local data = { "activated": true };
            _incomingCB(data);

            // Reboot the imp upon idle
            // (to allow writes to flash time to take place, etc.)
            imp.onidle(function() {
                imp.reset();
            }.bindenv(this));
        }.bindenv(this);
        _blinkup.clear <- function() {
            // Close the existing connection to the mobile app
            if (_incoming != null) _incoming.close();

            // Clear the WiFi settings ONLY - this will affect the next
            // disconnection/connection cycle, not the current connection
            imp.clearconfiguration(CONFIG_WIFI);
        }.bindenv(this);

        // We need to wait 0.01s for the BLE radio to boot, so see how
        // long the set-up took before sleeping (which may not be needed)
        now = hardware.millis() - now;
        if (now < 10) imp.sleep((10 - now) / 1000);

        try {
            // Instantiate Bluetooth LE
            // FROM 2.1.0 - use separate calls for imp004m and imp006 because of different bluetooth.open() parameter lists
            if (_impType == "imp004m") {
                ble = hardware.bluetooth.open(_uart, firmware);
            } else if (_impType == "imp006") {
                if (_version < BTLE_BLINKUP_MIN_IMPOS) {
                    ble = hardware.bluetooth.open(firmware);
                } else {
                    ble = hardware.bluetooth.open();
                }
            }
        } catch (err) {
            throw "BLE failed to initialize (error: " + err + ")";
        }
    }

    /**
     * This is the library's own handler for incoming connections.
     *
     * It calls the host app as required upon connection.
     * Issues data via the onConnect callback, if one has been registered.
     *
     * @private
     *
     * @param {imp::bluetoothconnection} conn - The connection's imp API BluetoothConnection instance.
     *
     */
    function _connectHandler(conn) {
        if (_incomingCB == null) return;

        // Save the connecting device's BluetoothConnection instance
        _incoming = conn;

        // Register the library's own onclose handler
        conn.onclose(_closeHandler.bindenv(this));

        // Package up the connection data for return to the host app
        local data = { "conn":     conn,
                       "address":  conn.address(),
                       "security": conn.security(),
                       "state":    "connected" };

        // Call the host app's onconnect handler
        _incomingCB(data);
    }

    /**
     * This is the library's own handler for broken connections.
     *
     * It calls the host app as required upon disconnection.
     * This will never be called if the host app did not provide onConnect() with a notification callback.
     * Issues data via the onConnect callback, if one has been registered.
     *
     * @private
     *
     * @param {imp::bluetoothconnection} conn - The connection's imp API BluetoothConnection instance.
     *
     */
    function _closeHandler() {
        if (_incomingCB == null) return;

        // Package up the connection data for return to the host app
        local data = { "conn":    _incoming,
                       "address": _incoming.address(),
                       "state":   "disconnected" };

        // Call the host app's onconnect handler
        _incomingCB(data);
    }

    /**
     * Convert a hex string to an integer.
     *
     * @private
     *
     * @param {string} hs - A string in hexadecimal format.
     *
     * @returns {integer} The integer that that source string represents.
     *
     */
    function _hexStringToInt(hs) {
        local i = 0;
        foreach (c in hs) {
            local n = c - '0';
            if (n > 9) n = ((n & 0x1F) - 7);
            i = (i << 4) + n;
        }
        return i;
    }

    /**
     * Scan for nearby WiFi networks compatible with the host imp.
     *
     * Sets the instance's internal list of nearby networks, '_networks'.
     *
     * @private
     *
     * @param {bool} [shouldLoop] - Whether we should queue up a repeat scan. Default: false.
     *
     */
    function _scan(shouldLoop = false) {
        // Make sure we're not sending BlinkUp data
        if (!_blinking) {
            _networks = imp.scanwifinetworks();

            // Check the list of WLANs for networks which have multiple reachable access points,
            // ie. networks of the same SSID but different BSSIDs, otherwise the same WLAN will
            // be listed twice
            local i = 0;
            do {
                local network = _networks[i];
                i++;
                for (local j = 0 ; j < _networks.len() ; j++) {
                    local aNetwork = _networks[j];
                    if (network.ssid == aNetwork.ssid && network.bssid != aNetwork.bssid) {
                        // We have two identical SSIDs but different base stations, so remove one
                        _networks.remove(j);
                    }
                }
            } while (_networks.len() > i);
        }

        // Should we schedule a network list refresh?
        if (shouldLoop) {
            // Yes, we should, after 'BTLE_BLINKUP_WIFI_SCAN_INTERVAL' seconds
            imp.wakeup(BTLE_BLINKUP_WIFI_SCAN_INTERVAL, function() {
                _scan(true);
            }.bindenv(this));
        }
    }

    /**
     * Check that the table of UUIDs supplied by the constructor has the correct keys.
     *
     * @private
     *
     * @param {table} [uuids] - The supplied Bluetooth service UUIDs.
     *
     * @returns {bool} Whether the table has the correct key names (true) or not (false).
     *
     */
    function _checkUUIDs(uuids) {
        // Make sure the UUIDs table contains the correct keys, which are:
        local keyList = ["blinkup_service_uuid", "ssid_setter_uuid", "password_setter_uuid",
                         "planid_setter_uuid", "token_setter_uuid", "blinkup_trigger_uuid",
                         "wifi_getter_uuid", "wifi_clear_trigger_uuid"];
        local got = 0;
        foreach (key in keyList) {
            if (uuids[key].len() != null) got++;
        }
        return got == 8 ? true : false;
    }
}
