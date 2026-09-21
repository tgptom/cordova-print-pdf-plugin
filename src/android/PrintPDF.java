package com.sgoldm.plugin.printPDF;

import android.annotation.TargetApi;
import android.content.Context;
import android.net.Uri;
import android.os.Bundle;
import android.os.CancellationSignal;
import android.os.ParcelFileDescriptor;
import android.print.PageRange;
import android.print.PrintAttributes;
import android.print.PrintDocumentAdapter;
import android.print.PrintDocumentInfo;
import android.print.PrintManager;
import android.util.Base64;

import org.apache.cordova.CallbackContext;
import org.apache.cordova.CordovaPlugin;
import org.apache.cordova.CordovaResourceApi;
import org.json.JSONArray;
import org.json.JSONException;

import java.io.ByteArrayInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * This plugin brings up a native overlay to print pdf documents.
 */
public class PrintPDF extends CordovaPlugin {

    public static final String ACTION_PRINT_DOCUMENT = "printDocument";
    public static final String ACTION_IS_PRINT_AVAILABLE = "isPrintingAvailable";
    private static final String DEFAULT_DOC_NAME = "unknown";
    private static final String DEFAULT_DOC_TYPE = "Data";
    private static final String FILE_DOC_TYPE = "File";

    @Override
    public boolean execute(String action, JSONArray args, CallbackContext callback) throws JSONException {
        if (ACTION_PRINT_DOCUMENT.equals(action)) {
            final String content = args.optString(0, "");
            final String type = args.optString(1, DEFAULT_DOC_TYPE);
            final String title = args.optString(2, DEFAULT_DOC_NAME);

            if (content == null || content.trim().isEmpty()) {
                sendError(callback, "Missing print data");
                return true;
            }

            printViaNative(content, type, title, callback);
            return true;
        } else if (ACTION_IS_PRINT_AVAILABLE.equals(action)) {
            callback.success(isPrintServiceAvailable());
            return true;
        }

        return false;
    }

    private boolean isPrintServiceAvailable() {
        PrintManager printManager = (PrintManager) cordova.getActivity().getSystemService(Context.PRINT_SERVICE);
        return printManager != null;
    }

    private InputStream convertContentToInputStream(final String content, final String type) throws IOException {
        if (type != null && type.compareToIgnoreCase(FILE_DOC_TYPE) == 0) {
            Uri fileUri = Uri.parse(content);
            if (fileUri == null) {
                throw new IOException("Invalid file URI");
            }

            CordovaResourceApi resourceApi = webView.getResourceApi();
            Uri remappedUri = resourceApi.remapUri(fileUri);
            CordovaResourceApi.OpenForReadResult readResult = resourceApi.openForRead(remappedUri);
            if (readResult == null || readResult.inputStream == null) {
                throw new IOException("Unable to open file");
            }
            return readResult.inputStream;
        }

        try {
            byte[] pdfAsBytes = Base64.decode(content, Base64.DEFAULT);
            if (pdfAsBytes == null || pdfAsBytes.length == 0) {
                throw new IOException("Invalid Base64 PDF data");
            }
            return new ByteArrayInputStream(pdfAsBytes);
        } catch (IllegalArgumentException e) {
            throw new IOException("Invalid Base64 PDF data", e);
        }
    }

    private void sendError(CallbackContext callbackContext, String errorMessage) {
        callbackContext.error("{\"success\": false, \"available\": true, \"error\": \"" + escapeJson(errorMessage) + "\"}");
    }

    private void sendDismissed(CallbackContext callbackContext) {
        callbackContext.error("{\"success\": false, \"available\": true, \"dismissed\": true }");
    }

    private void sendUnavailable(CallbackContext callbackContext, String errorMessage) {
        callbackContext.error("{\"success\": false, \"available\": false, \"error\": \"" + escapeJson(errorMessage) + "\"}");
    }

    private void sendSuccess(CallbackContext callbackContext) {
        callbackContext.success("{\"success\": true, \"available\": true }");
    }

    private String escapeJson(String value) {
        if (value == null) {
            return "Unknown error";
        }
        return value.replace("\\", "\\\\").replace("\"", "\\\"");
    }

    @TargetApi(19)
    private void printViaNative(final String content, final String type, final String title,
                                final CallbackContext callbackContext) {
        final AtomicBoolean callbackCompleted = new AtomicBoolean(false);
        final AtomicBoolean writeSucceeded = new AtomicBoolean(false);

        final Runnable sendDismissedOnce = new Runnable() {
            @Override
            public void run() {
                if (callbackCompleted.compareAndSet(false, true)) {
                    sendDismissed(callbackContext);
                }
            }
        };

        final Runnable sendSuccessOnce = new Runnable() {
            @Override
            public void run() {
                if (callbackCompleted.compareAndSet(false, true)) {
                    sendSuccess(callbackContext);
                }
            }
        };

        final ErrorCallback sendErrorOnce = new ErrorCallback() {
            @Override
            public void onError(String message) {
                if (callbackCompleted.compareAndSet(false, true)) {
                    sendError(callbackContext, message);
                }
            }
        };

        cordova.getActivity().runOnUiThread(new Runnable() {
            @Override
            public void run() {
                PrintManager printManager = (PrintManager) cordova.getActivity().getSystemService(Context.PRINT_SERVICE);
                if (printManager == null) {
                    if (callbackCompleted.compareAndSet(false, true)) {
                        sendUnavailable(callbackContext, "Printing is not available");
                    }
                    return;
                }

                PrintDocumentAdapter pda = new PrintDocumentAdapter() {
                    @Override
                    public void onWrite(PageRange[] pages, ParcelFileDescriptor destination,
                                        CancellationSignal cancellationSignal,
                                        WriteResultCallback callback) {
                        if (cancellationSignal != null && cancellationSignal.isCanceled()) {
                            callback.onWriteCancelled();
                            sendDismissedOnce.run();
                            return;
                        }

                        try (InputStream input = convertContentToInputStream(content, type);
                             FileOutputStream output = new FileOutputStream(destination.getFileDescriptor())) {
                            byte[] buf = new byte[8192];
                            int bytesRead;

                            while ((bytesRead = input.read(buf)) > 0) {
                                if (cancellationSignal != null && cancellationSignal.isCanceled()) {
                                    callback.onWriteCancelled();
                                    sendDismissedOnce.run();
                                    return;
                                }
                                output.write(buf, 0, bytesRead);
                            }

                            output.flush();
                            writeSucceeded.set(true);
                            callback.onWriteFinished(new PageRange[] { PageRange.ALL_PAGES });
                        } catch (IOException e) {
                            callback.onWriteFailed(e.getMessage());
                            sendErrorOnce.onError(e.getMessage());
                        }
                    }

                    @Override
                    public void onLayout(PrintAttributes oldAttributes, PrintAttributes newAttributes,
                                         CancellationSignal cancellationSignal,
                                         LayoutResultCallback callback, Bundle extras) {
                        if (cancellationSignal != null && cancellationSignal.isCanceled()) {
                            callback.onLayoutCancelled();
                            sendDismissedOnce.run();
                            return;
                        }

                        PrintDocumentInfo pdi = new PrintDocumentInfo.Builder(title)
                                .setContentType(PrintDocumentInfo.CONTENT_TYPE_DOCUMENT)
                                .build();
                        callback.onLayoutFinished(pdi, true);
                    }

                    @Override
                    public void onFinish() {
                        if (writeSucceeded.get()) {
                            sendSuccessOnce.run();
                        } else {
                            if (callbackCompleted.compareAndSet(false, true)) {
                                sendError(callbackContext, "Printing was cancelled");
                            }
                        }
                    }
                };

                try {
                    printManager.print(title, pda, null);
                } catch (RuntimeException e) {
                    sendErrorOnce.onError(e.getMessage());
                }
            }
        });
    }

    private interface ErrorCallback {
        void onError(String message);
    }
}
