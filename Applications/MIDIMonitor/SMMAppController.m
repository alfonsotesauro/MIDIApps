/*
 Copyright (c) 2001-2014, Kurt Revis.  All rights reserved.
 
 Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
 
 * Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
 * Neither the name of Kurt Revis, nor Snoize, nor the names of other contributors may be used to endorse or promote products derived from this software without specific prior written permission.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "SMMAppController.h"

#import <CoreMIDI/CoreMIDI.h>
#import <SnoizeMIDI/SnoizeMIDI.h>
#import <Sparkle/Sparkle.h>

#import "SMMDocument.h"
#import "SMMMonitorWindowController.h"
#import "SMMPreferencesWindowController.h"


NSString* const SMMOpenWindowsForNewSourcesPreferenceKey = @"SMMOpenWindowsForNewSources";

@interface SMMAppController () <SUUpdaterDelegate>

@property (nonatomic, assign) BOOL shouldOpenUntitledDocument;
@property (nonatomic, retain) NSMutableSet *newlyAppearedSources;

@end

@implementation SMMAppController

- (void)dealloc
{
    // Appease the analyzer
    [_newlyAppearedSources release];
    [super dealloc];
}

- (void)applicationWillFinishLaunching:(NSNotification *)notification
{
    // Before CoreMIDI is initialized, make sure the spying driver is installed
    NSError* installError = MIDISpyInstallDriverIfNecessary();

    // Initialize CoreMIDI while the app's icon is still bouncing, so we don't have a large pause after it stops bouncing
    // but before the app's window opens.  (CoreMIDI needs to find and possibly start its server process, which can take a while.)
    if ([SMClient sharedClient] == nil) {
        NSBundle *bundle = SMBundleForObject(self);
        NSAlert *alert = [[NSAlert alloc] init];
        alert.alertStyle = NSAlertStyleCritical;
        alert.messageText = NSLocalizedStringFromTableInBundle(@"The MIDI system could not be started.", @"MIDIMonitor", bundle, "error message if MIDI initialization fails");
        alert.informativeText = NSLocalizedStringFromTableInBundle(@"This probably affects all apps that use MIDI, not just MIDI Monitor.\n\nMost likely, the cause is a bad MIDI driver. Remove any MIDI drivers that you don't recognize, then try again.", @"MIDIMonitor", bundle, "informative text if MIDI initialization fails");
        [alert addButtonWithTitle:NSLocalizedStringFromTableInBundle(@"Quit", @"MIDIMonitor", bundle, "title of quit button")];
        [alert addButtonWithTitle:NSLocalizedStringFromTableInBundle(@"Show MIDI Drivers",  @"MIDIMonitor", bundle, "Show MIDI Drivers button after MIDI spy client creation fails")];

        if ([alert runModal] == NSAlertSecondButtonReturn) {
            [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:@"/Library/Audio/MIDI Drivers"]];
        }

        [alert release];
        [NSApp terminate:nil];
        return;
    }

    // After this point, we are OK to open documents (untitled or otherwise)
    self.shouldOpenUntitledDocument = YES;

    if (!installError) {
        // Create our client for spying on MIDI output.
        OSStatus status = MIDISpyClientCreate(&_midiSpyClient);
        if (status != noErr) {
            NSBundle *bundle = SMBundleForObject(self);
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = NSLocalizedStringFromTableInBundle(@"MIDI Monitor could not make a connection to its MIDI driver.", @"MIDIMonitor", bundle, "error message if MIDI spy client creation fails");
            alert.informativeText = NSLocalizedStringFromTableInBundle(@"If you continue, MIDI Monitor will not be able to see the output of other MIDI applications, but all other features will still work.\n\nTo fix the problem, restart your computer.", @"MIDIMonitor", bundle, "second line of warning when MIDI spy is unavailable");
            [alert addButtonWithTitle:NSLocalizedStringFromTableInBundle(@"Continue", @"MIDIMonitor", bundle, "Continue button after MIDI spy client creation fails")];
            [alert addButtonWithTitle:NSLocalizedStringFromTableInBundle(@"Restart Now",  @"MIDIMonitor", bundle, "Restart button after MIDI spy client creation fails")];

            if ([alert runModal] == NSAlertSecondButtonReturn) { // Restart
                NSAppleScript *appleScript = [[NSAppleScript alloc] initWithSource:@"tell application \"Finder\" to restart"];
                [appleScript executeAndReturnError:NULL];
                [appleScript release];
            }

            [alert release];
        }
    }
    else {  // Failure to install
        NSAlert *alert = [NSAlert alertWithError:installError];
        [alert runModal];
    }

    /*

        case kMIDISpyDriverCouldNotRemoveOldDriver: {
            NSURL *driversURL = MIDISpyUserMIDIDriversURL();    // should be non-nil, but might be nil if there's a really weird error

            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = NSLocalizedStringFromTableInBundle(@"MIDI Monitor tried to install a new version of its MIDI driver, but it could not remove the old version.", @"MIDIMonitor", bundle, "error message if MIDI spy driver installation fails because couldn't remove");
            alert.informativeText = NSLocalizedStringFromTableInBundle(@"To fix this, remove the old driver.\n\nMIDI Monitor will not be able to see the output of other MIDI applications, but all other features will still work.", @"MIDIMonitor", bundle, "error message if old MIDI spy driver could not be removed");
            [alert addButtonWithTitle:NSLocalizedStringFromTableInBundle(@"Continue", @"MIDIMonitor", bundle, "Continue button after MIDI spy driver installation fails")];
            alert.buttons[0].tag = 0;
            if (driversURL) {
                [alert addButtonWithTitle:NSLocalizedStringFromTableInBundle(@"Show Driver Location",  @"MIDIMonitor", bundle, "Show Driver Location button after MIDI spy driver installation fails because couldn't remove")];
                alert.buttons[1].tag = 1;
            }

            if ([alert runModal] == 1) { // Show Driver Location
                [[NSWorkspace sharedWorkspace] selectFile:driversURL.path inFileViewerRootedAtPath:@""];
            }

            [alert release];
            break;
        }

        case kMIDISpyDriverInstallationFailed:
        default: {
            NSURL *driversURL = MIDISpyUserMIDIDriversURL();    // should be non-nil, but might be nil if there's a really weird error

            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = NSLocalizedStringFromTableInBundle(@"MIDI Monitor tried to install a MIDI driver, but it failed.", @"MIDIMonitor", bundle, "error message if MIDI spy driver installation fails");
            alert.informativeText = NSLocalizedStringFromTableInBundle(@"The privileges of the install location might not allow write access.\n\nMIDI Monitor will not be able to see the output of other MIDI applications, but all other features will still work.", @"MIDIMonitor", bundle, "second line of warning when MIDI spy driver installation fails");
            [alert addButtonWithTitle:NSLocalizedStringFromTableInBundle(@"Continue", @"MIDIMonitor", bundle, "Continue button after MIDI spy driver installation fails")];
            alert.buttons[0].tag = 0;
            if (driversURL) {
                [alert addButtonWithTitle:NSLocalizedStringFromTableInBundle(@"Show Install Location",  @"MIDIMonitor", bundle, "Show Install Location button after MIDI spy driver installation fails")];
                alert.buttons[1].tag = 1;
            }

            if ([alert runModal] == 1) { // Show Install Location
                [[NSWorkspace sharedWorkspace] selectFile:driversURL.path inFileViewerRootedAtPath:@""];
            }

            [alert release];
            break;
        }
    */
}

- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender
{
    return self.shouldOpenUntitledDocument;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    // Listen for new source endpoints. Don't do this earlier--we only are interested in ones
    // that appear after we've been launched.
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sourceEndpointsAppeared:) name:SMMIDIObjectsAppearedNotification object:[SMSourceEndpoint class]];
}

- (IBAction)showPreferences:(id)sender
{
    [[SMMPreferencesWindowController preferencesWindowController] showWindow:nil];
}

- (IBAction)showAboutBox:(id)sender
{
    NSMutableDictionary *options = [[NSMutableDictionary alloc] init];
    options[@"Version"] = @"";

    // The RTF file Credits.rtf has foreground text color = black, but that's wrong for 10.14 dark mode.
    // Similarly the font is not necessarily the systme font. Override both.
    if (@available(macOS 10.13, *)) {
        NSURL *creditsURL = [[NSBundle mainBundle] URLForResource:@"Credits" withExtension:@"rtf"];
        if (creditsURL) {
            NSMutableAttributedString *credits = [[NSMutableAttributedString alloc] initWithURL:creditsURL documentAttributes:NULL];
            NSRange range = NSMakeRange(0, credits.length);
            [credits addAttribute:NSFontAttributeName value:[NSFont labelFontOfSize:[NSFont labelFontSize]] range:range];
            if (@available(macOS 10.14, *)) {
                [credits addAttribute:NSForegroundColorAttributeName value:[NSColor labelColor] range:range];
            }
            options[NSAboutPanelOptionCredits] = credits;
            [credits release];
        }
    }

    [NSApp orderFrontStandardAboutPanelWithOptions:options];

    [options release];
}

- (IBAction)showHelp:(id)sender
{
    NSString *message = nil;
    
    NSString *path = [SMBundleForObject(self) pathForResource:@"docs" ofType:@"htmld"];
    if (path) {
        path = [path stringByAppendingPathComponent:@"index.html"];
        if (![[NSWorkspace sharedWorkspace] openFile:path]) {
            message = NSLocalizedStringFromTableInBundle(@"The help file could not be opened.", @"MIDIMonitor", SMBundleForObject(self), "error message if opening the help file fails");
        }
    } else {
        message = NSLocalizedStringFromTableInBundle(@"The help file could not be found.", @"MIDIMonitor", SMBundleForObject(self), "error message if help file can't be found");
    }

    if (message) {
        NSString *title = NSLocalizedStringFromTableInBundle(@"Error", @"MIDIMonitor", SMBundleForObject(self), "title of error alert");
        NSRunAlertPanel(title, @"%@", nil, nil, nil, message);
    }
}

- (IBAction)sendFeedback:(id)sender
{
    BOOL success = NO;

    NSString *feedbackEmailAddress = @"MIDIMonitor@snoize.com";	// Don't localize this
    NSString *feedbackEmailSubject = NSLocalizedStringFromTableInBundle(@"MIDI Monitor Feedback", @"MIDIMonitor", SMBundleForObject(self), "subject of feedback email");
    NSString *mailToURLString = [NSString stringWithFormat:@"mailto:%@?Subject=%@", feedbackEmailAddress, feedbackEmailSubject];
	mailToURLString = [(NSString*)CFURLCreateStringByAddingPercentEscapes(NULL, (CFStringRef)mailToURLString, NULL, NULL, kCFStringEncodingUTF8) autorelease];
    NSURL *mailToURL = [NSURL URLWithString:mailToURLString];
    if (mailToURL) {
        success = [[NSWorkspace sharedWorkspace] openURL:mailToURL];
    }

    if (!success) {
        NSLog(@"Couldn't send feedback: url string was <%@>, url was <%@>", mailToURLString, mailToURL);

        NSString *title = NSLocalizedStringFromTableInBundle(@"Error", @"MIDIMonitor", SMBundleForObject(self), "title of error alert");
        NSString *message = NSLocalizedStringFromTableInBundle(@"MIDI Monitor could not ask your email application to create a new message, so you will have to do it yourself. Please send your email to this address:\n%@\nThank you!", @"MIDIMonitor", SMBundleForObject(self), "message of alert when can't send feedback email");
        
        NSRunAlertPanel(title, message, nil, nil, nil, feedbackEmailAddress);
    }
}

- (IBAction)restartMIDI:(id)sender
{
    OSStatus status = MIDIRestart();
    if (status) {
        // Something went wrong!
        NSString *message = NSLocalizedStringFromTableInBundle(@"Rescanning the MIDI system resulted in an unexpected error (%d).", @"MIDIMonitor", SMBundleForObject(self), "error message if MIDIRestart() fails");
        NSString *title = NSLocalizedStringFromTableInBundle(@"MIDI Error", @"MIDIMonitor", SMBundleForObject(self), "title of MIDI error panel");

        NSRunAlertPanel(title, message, nil, nil, nil, status);        
    }
}

#pragma mark SUUpdaterDelegate

- (BOOL)updater:(SUUpdater *)updater shouldPostponeRelaunchForUpdate:(SUAppcastItem *)item untilInvoking:(NSInvocation *)invocation
{
    // The update might contain a MIDI driver that needs to get
    // installed. In order for it to work immediately,
    // we want the MIDIServer to shut down now, so we can install
    // the driver and then trigger the MIDIServer to run again.

    // Remove our connections to the MIDIServer first:
    [SMClient disposeSharedClient];
    MIDISpyClientDispose(_midiSpyClient);
    MIDISpyClientDisposeSharedMIDIClient();

    // Wait a few seconds for the MIDIServer to hopefully shut down,
    // then relaunch for the update:
    [invocation retain];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [invocation invoke];
        [invocation release];
    });

    return YES;
}

#pragma mark Private

- (void)sourceEndpointsAppeared:(NSNotification *)notification
{
    if ([[NSUserDefaults standardUserDefaults] boolForKey:SMMOpenWindowsForNewSourcesPreferenceKey]) {
        NSArray *endpoints = [[notification userInfo] objectForKey:SMMIDIObjectsThatAppeared];

        if (!self.newlyAppearedSources) {
            self.newlyAppearedSources = [NSMutableSet set];
            [self performSelector:@selector(openWindowForNewlyAppearedSources) withObject:nil afterDelay:0.1 inModes:@[NSDefaultRunLoopMode]];
        }
        [self.newlyAppearedSources addObjectsFromArray:endpoints];
    }
}

- (void)openWindowForNewlyAppearedSources
{
    NSDocumentController *dc = [NSDocumentController sharedDocumentController];
    SMMDocument *document = [dc openUntitledDocumentAndDisplay:NO error:NULL];
    [document makeWindowControllers];
    [document setSelectedInputSources:self.newlyAppearedSources];
    [document showWindows];
    SMMMonitorWindowController *wc = document.windowControllers.firstObject;
    [wc revealInputSources:self.newlyAppearedSources];
    [document updateChangeCount:NSChangeCleared];

    self.newlyAppearedSources = nil;
}

@end
