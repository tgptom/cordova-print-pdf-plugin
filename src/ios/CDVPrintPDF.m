//
//  CDVPrintPDF.m
//  Print PDF
//
//  Created by Sarah Goldman (github.com/sarahgoldman) on 07/06/2015.
//  Copyright 2015 Sarah Goldman. All rights reserved.
//  MIT licensed
//

#import "CDVPrintPDF.h"
#import "CDVFile.h"

@interface CDVPrintPDF (Private)
- (BOOL)isPrintServiceAvailable;
- (void)sendErrorWithMessage:(NSString*)message callbackId:(NSString*)callbackId;
- (NSString*)safeCallbackIdFromCommand:(CDVInvokedUrlCommand*)command;
- (NSString*)resolvedPathForFileURLString:(NSString*)fileUrlString;
+ (NSString*)escapeForJson:(NSString*)value;
@end

@implementation CDVPrintPDF

NSString * const KEY_TYPE_FILE = @"File";

@synthesize successCallback, failCallback, wasDismissed;

- (void)isPrintingAvailable:(CDVInvokedUrlCommand*)command
{
    NSString *callbackId = [self safeCallbackIdFromCommand:command];
    if (callbackId == nil) {
        return;
    }

    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                         messageAsBool:([self isPrintServiceAvailable] ? YES : NO)];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
}

- (void)printDocument:(CDVInvokedUrlCommand *)command
{
    NSString *callbackId = [self safeCallbackIdFromCommand:command];
    if (callbackId == nil) {
        return;
    }

    if (command.arguments == nil || command.arguments.count < 1) {
        [self sendErrorWithMessage:@"Missing print data" callbackId:callbackId];
        return;
    }

    NSString *pdfString = [command.arguments objectAtIndex:0];
    NSString *typeData = command.arguments.count > 1 ? [command.arguments objectAtIndex:1] : nil;

    if (![pdfString isKindOfClass:[NSString class]] || pdfString.length == 0) {
        [self sendErrorWithMessage:@"Missing print data" callbackId:callbackId];
        return;
    }

    NSData *pdfData = nil;
    if (typeData != nil && [typeData isKindOfClass:[NSString class]] && [typeData isEqualToString:KEY_TYPE_FILE]) {
        NSString *filePath = [self resolvedPathForFileURLString:pdfString];
        if (filePath == nil || filePath.length == 0) {
            [self sendErrorWithMessage:@"Unable to resolve file path" callbackId:callbackId];
            return;
        }

        NSFileManager *fileMgr = [NSFileManager defaultManager];
        BOOL isDirectory = NO;
        if (![fileMgr fileExistsAtPath:filePath isDirectory:&isDirectory] || isDirectory) {
            [self sendErrorWithMessage:@"File does not exist" callbackId:callbackId];
            return;
        }

        if (![fileMgr isReadableFileAtPath:filePath]) {
            [self sendErrorWithMessage:@"File is not readable" callbackId:callbackId];
            return;
        }

        NSError *readError = nil;
        pdfData = [NSData dataWithContentsOfFile:filePath options:0 error:&readError];
        if (pdfData == nil || pdfData.length == 0) {
            NSString *readErrorMessage = readError != nil ? readError.localizedDescription : @"Unable to read file";
            [self sendErrorWithMessage:readErrorMessage callbackId:callbackId];
            return;
        }
    } else {
        pdfData = [[NSData alloc] initWithBase64EncodedString:pdfString options:0];
        if (pdfData == nil || pdfData.length == 0) {
            [self sendErrorWithMessage:@"Invalid Base64 PDF data" callbackId:callbackId];
            return;
        }
    }

    self.wasDismissed = NO;

    if (![self isPrintServiceAvailable]) {
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                           messageAsString:@"{\"success\": false, \"available\": false, \"error\": \"Printing is not available\"}"];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
        return;
    }

    UIPrintInteractionController *printInteraction = [UIPrintInteractionController sharedPrintController];
    if (!printInteraction) {
        [self sendErrorWithMessage:@"Unable to present print dialog" callbackId:callbackId];
        return;
    }

    UIPrintInfo *printInfo = [UIPrintInfo printInfo];
    printInfo.outputType = UIPrintInfoOutputGeneral;
    printInteraction.printInfo = printInfo;
    printInteraction.showsPageRange = YES;
    printInteraction.printingItem = pdfData;
    printInteraction.delegate = self;

    void (^completionHandler)(UIPrintInteractionController *, BOOL, NSError *) =
    ^(UIPrintInteractionController *printController, BOOL completed, NSError *error) {
        CDVPluginResult* pluginResult = nil;
        if (!completed || error) {
            if (self.wasDismissed) {
                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                 messageAsString:@"{\"success\": false, \"available\": true, \"dismissed\": true}"];
            } else if (error != nil) {
                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                 messageAsString:[NSString stringWithFormat:@"{\"success\": false, \"available\": true, \"error\": \"%@\", \"dismissed\": false}",
                                                                  [self.class escapeForJson:error.localizedDescription]]];
            } else {
                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                 messageAsString:@"{\"success\": false, \"available\": true, \"dismissed\": false}"];
            }
        } else {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                             messageAsString:@"{\"success\": true}"];
        }
        [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
    };

    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        UIView *anchorView = self.viewController.view;
        if (anchorView == nil) {
            [self sendErrorWithMessage:@"Unable to present print dialog" callbackId:callbackId];
            return;
        }

        CGRect bounds = anchorView.bounds;
        NSInteger dialogX = command.arguments.count > 2 ? [[command.arguments objectAtIndex:2] integerValue] : -1;
        NSInteger dialogY = command.arguments.count > 3 ? [[command.arguments objectAtIndex:3] integerValue] : -1;

        if (dialogX < 0 || dialogX > CGRectGetMaxX(bounds)) {
            dialogX = (NSInteger)CGRectGetMidX(bounds);
        }

        if (dialogY < 0 || dialogY > CGRectGetMaxY(bounds)) {
            dialogY = (NSInteger)CGRectGetMidY(bounds);
        }

        [printInteraction presentFromRect:CGRectMake(dialogX, dialogY, 1, 1)
                                   inView:anchorView
                                 animated:YES
                        completionHandler:completionHandler];
    } else {
        [printInteraction presentAnimated:YES completionHandler:completionHandler];
    }
}

- (void)dismissPrintDialog:(CDVInvokedUrlCommand*)command
{
    self.wasDismissed = YES;
    [[UIPrintInteractionController sharedPrintController] dismissAnimated:NO];
}

- (BOOL)isPrintServiceAvailable
{
    Class myClass = NSClassFromString(@"UIPrintInteractionController");
    if (myClass) {
        UIPrintInteractionController *controller = [UIPrintInteractionController sharedPrintController];
        return (controller != nil) && [UIPrintInteractionController isPrintingAvailable];
    }

    return NO;
}

- (void)printInteractionControllerDidDismissPrinterOptions:(UIPrintInteractionController *)printInteractionController
{
    self.wasDismissed = YES;
}

- (void)sendErrorWithMessage:(NSString*)message callbackId:(NSString*)callbackId
{
    NSString *errorMessage = [CDVPrintPDF escapeForJson:message != nil ? message : @"Unknown error"];
    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                       messageAsString:[NSString stringWithFormat:@"{\"success\": false, \"available\": true, \"error\": \"%@\"}", errorMessage]];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
}

- (NSString*)safeCallbackIdFromCommand:(CDVInvokedUrlCommand*)command
{
    if (command == nil || command.callbackId == nil || command.callbackId.length == 0) {
        return nil;
    }

    return command.callbackId;
}

- (NSString*)resolvedPathForFileURLString:(NSString*)fileUrlString
{
    if (fileUrlString == nil || fileUrlString.length == 0) {
        return nil;
    }

    CDVFilesystemURL *urlCdv = [CDVFilesystemURL fileSystemURLWithString:fileUrlString];
    if (urlCdv != nil) {
        CDVFile* filePlugin = [self.commandDelegate getCommandInstance:@"File"];
        if (filePlugin != nil) {
            NSString *filePath = [filePlugin filesystemPathForURL:urlCdv];
            if (filePath != nil && filePath.length > 0) {
                return filePath;
            }
        }
    }

    NSURL *fileURL = [NSURL URLWithString:fileUrlString];
    if (fileURL != nil && fileURL.fileURL) {
        return fileURL.path;
    }

    if ([fileUrlString hasPrefix:@"/"]) {
        return fileUrlString;
    }

    return nil;
}

+ (NSString*)escapeForJson:(NSString*)value
{
    if (value == nil) {
        return @"Unknown error";
    }

    NSString *escaped = [value stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"\r" withString:@"\\r"];
    return escaped;
}

@end
