var exec = require('cordova/exec');
var channel = require('cordova/channel');

function getPlatformId() {
    if (typeof cordova !== 'undefined' && cordova.platformId) {
        return cordova.platformId.toLowerCase();
    }

    if (typeof device !== 'undefined' && device.platform) {
        return device.platform.toLowerCase();
    }

    return '';
}

/**
 * @constructor
 */
var PrintPDF = function () {
    this.METHOD = 'printDocument';
    this.IS_AVAILABLE_METHOD = 'isPrintingAvailable';
    this.DISMISS_METHOD = 'dismissPrintDialog';
    this.CLASS = 'PrintPDF';
};

PrintPDF.prototype.print = function (options) {
    options = options || {};

    var data = options.data;
    var type = options.type || 'Data';
    var title = options.title || 'Print Document';

    var dialogX = options.dialogX || -1;
    var dialogY = options.dialogY || -1;

    var successCallback = (options.success && typeof options.success === 'function') ? options.success : this.defaultCallback;
    var errorCallback = (options.error && typeof options.error === 'function') ? options.error : this.defaultCallback;

    if (!data) {
        if (errorCallback) {
            errorCallback({
                success: false,
                error: "Parameter 'data' is required."
            });
        }
        return false;
    }

    var args = [data, type];

    if (getPlatformId() === 'ios') {
        args.push(dialogX);
        args.push(dialogY);
    } else {
        args.push(title);
    }

    exec(successCallback, errorCallback, this.CLASS, this.METHOD, args);
    return true;
};

PrintPDF.prototype.isPrintingAvailable = function (callback) {
    var successCallback = (callback && typeof callback === 'function') ? callback : this.defaultCallback;
    exec(successCallback, null, this.CLASS, this.IS_AVAILABLE_METHOD, []);
};

PrintPDF.prototype.dismiss = function () {
    if (getPlatformId() === 'ios') {
        exec(null, null, this.CLASS, this.DISMISS_METHOD, []);
    }
};

PrintPDF.prototype.defaultCallback = null;

var pluginInstance = new PrintPDF();

channel.onCordovaReady.subscribe(function () {
    window.plugins = window.plugins || {};
    window.plugins.PrintPDF = pluginInstance;
});

module.exports = pluginInstance;
