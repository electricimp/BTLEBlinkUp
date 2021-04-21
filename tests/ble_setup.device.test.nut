/**
 * BLEBlinkUp Library test cases
 *
 */
@include "github:electricimp/BluetoothFirmware/bt_firmware.lib.nut"


class BLESetupTestCase extends ImpTestCase {

    _ble = null;
    _iType = null;
    _isCompatible = false;

    /**
     * Get the imp Type (impp04m or imp006)
     */
    function setUp() {

        this.info("BTLEBlinkUp library version " + BTLEBlinkUp.VERSION);

        // Get the test imp’s type and report
        _iType = imp.info().type;
        this.info("Tests running on an " + _iType);

        // Check that the imp is compatible
        _isCompatible = (_iType == "imp006" || _iType == "imp004m");
        this.assertTrue(_isCompatible, "Tests attempted on an incompatible imp");
        this.info("Tests running on a compatible imp");

        // Instatiate the class
        _ble = BTLEBlinkUp(_initUUIDs(), (this._iType == "imp004m" ? BT_FIRMWARE.CYW_43438 : BT_FIRMWARE.CYW_43455));

        local result = (_ble != null);
        this.assertTrue(result, "BLE BlinkUp NOT running on " + this._iType);
        return "BLE BlinkUp running";
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