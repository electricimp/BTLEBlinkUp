/**
 * BLEBlinkUp Library test cases
 * Configuration with enable pin
 */

const BTLE_BLINKUP_MIN_IMPOS = 41.28;

@include "github:electricimp/BluetoothFirmware/bt_firmware.lib.nut"
@include "github:electricimp/BTLEBlinkUp/btleblinkup.device.lib.nut@develop"

class BLESetupTestCase extends ImpTestCase {

    _ble = null;
    _iType = null;
    _isCompatible = false;
    _impOSVersion = "41";

    function setUp() {

        // Get the impOS version
        local version = imp.getsoftwareversion();
        local pos = version.find("release");
        _impOSVersion = version.slice(pos + 8, pos + 13).tofloat();

        // Get the test imp’s type and report
        _iType = imp.info().type;
        this.info("Test running on an " + _iType + " (impOS " + _impOSVersion + ")");

        if (_iType == "imp006") {
            if (_impOSVersion < BTLE_BLINKUP_MIN_IMPOS) {
                // Need to be running BTLEBlinkUp 2.0.0
                this.assertTrue(BTLEBlinkUp.VERSION == "2.0.0", "Test run on imp006 with impOS < 41.28 -- test with BTLEBlinkUp 2.0.0");
            } else {
                // Need to be running BTLEBlinkUp 3.0.0
                this.assertTrue(BTLEBlinkUp.VERSION == "3.0.0", "Test run on imp006 with impOS >= 41.28 -- test with BTLEBlinkUp 3.0.0");
            }
        }

        // Check that the imp is compatible
        _isCompatible = (_iType == "imp006" || _iType == "imp004m");
        this.assertTrue(_isCompatible, "Test run on an incompatible imp");
        return "Test running on a compatible imp";
    }

    function testBLEInitReadout() {

        // Instantiate Bluetooth on a compatible device
        if (_isCompatible) {
            _ble = this._iType == "imp004m" ? BTLEBlinkUp(_initUUIDs(), BT_FIRMWARE.CYW_43438) : (_impOSVersion < BTLE_BLINKUP_MIN_IMPOS ? BTLEBlinkUp(_initUUIDs(), BT_FIRMWARE.CYW_43455) : BTLEBlinkUp(_initUUIDs()));

            local result = (_ble != null);
            this.assertTrue(result, "BLEBlinkUp NOT running on " + this._iType);
            return "BLEBlinkUp running";
        }

        this.assertTrue(_isCompatible, "Test run on an incompatible imp");
        return;
    }

    // Auxilliary funtion to set the GATT service UUIDs we wil use
    // NOTE Take from the Bluetooth BlinkUp sample code
    function _initUUIDs() {
        local uuids = {};
        uuids.blinkup_service_uuid    <- "FADA47BEC45548C9A5F2AF7CF368D719";
        uuids.ssid_setter_uuid        <- "5EBA195632D347C681A6A7E59F18DAC0";
        uuids.password_setter_uuid    <- "ED694AB947564528AA3A799A4FD11117";
        uuids.planid_setter_uuid      <- "A90AB0DC7B5C439A9AB52107E0BD816E";
        uuids.token_setter_uuid       <- "BD107D3E48784F6DAF3DDA3B234FF584";
        uuids.blinkup_trigger_uuid    <- "F299C3428A8A4544AC4208C841737B1B";
        uuids.wifi_getter_uuid        <- "57A9ED95ADD54913849457759B79A46C";
        uuids.wifi_clear_trigger_uuid <- "2BE5DDBA32864D09A652F24FAA514AF5";
        return uuids;
    }

}
