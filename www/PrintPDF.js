/**
 * @constructor
 */
var PrintPDF = function () {};

PrintPDF.prototype.print = function (url, title, successCallback, errorCallback) {

    if (!(url instanceof Array)) {
        url = [url];
    }

    if (device.platform == "Android") {

        var code = 'javascript:printDialog.setPrintDocument("url", "'+title+'", "'+url[0]+'");';
        var ref = window.open('https://www.google.com/cloudprint/dialog.html', '_blank', 'location=yes');
        ref.addEventListener('loadstop', function (event) {
            //wait 1 second till printDialog object is initialized
            setTimeout(function () {
                ref.executeScript({
                    code: code,
                }, function () {
                    console.log('document assigned successfully to google cloud print dialog');
                    successCallback();
                });
            }, 1000);

        });
    } else {
        cordova.exec(successCallback, errorCallback, 'PrintPDF', 'print', url);
    }
};

PrintPDF.prototype.isPrintingAvailable = function (successCallback, errorCallback) {
    cordova.exec(successCallback, errorCallback, 'PrintPDF', 'isPrintingAvailable', []);
};

// Plug in to Cordova
cordova.addConstructor(function () {

    if (!window.Cordova) {
        window.Cordova = cordova;
    };

    if (!window.plugins) window.plugins = {};
    window.plugins.PrintPDF = new PrintPDF();
});
