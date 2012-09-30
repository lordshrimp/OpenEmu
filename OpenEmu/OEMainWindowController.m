/*
 Copyright (c) 2011, OpenEmu Team
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
     * Redistributions of source code must retain the above copyright
       notice, this list of conditions and the following disclaimer.
     * Redistributions in binary form must reproduce the above copyright
       notice, this list of conditions and the following disclaimer in the
       documentation and/or other materials provided with the distribution.
     * Neither the name of the OpenEmu Team nor the
       names of its contributors may be used to endorse or promote products
       derived from this software without specific prior written permission.
 
 THIS SOFTWARE IS PROVIDED BY OpenEmu Team ''AS IS'' AND ANY
 EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL OpenEmu Team BE LIABLE FOR ANY
 DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "OEMainWindowController.h"
#import "OEMainWindowContentController.h"

#import "NSImage+OEDrawingAdditions.h"
#import "OEMainWindow.h"
#import "NSWindow+OEFullScreenAdditions.h"
#import "OESetupAssistant.h"
#import "OELibraryController.h"

#import "NSViewController+OEAdditions.h"
#import "OEGameDocument.h"
#import "OEGameViewController.h"

#import "OEHUDAlert+DefaultAlertsAdditions.h"
#import "OEDBGame.h"

#import "NSView+FadeImage.h"
#import "OEFadeView.h"

NSString *const OEForcePopoutGameWindowKey = @"forcePopout";
NSString *const OEFullScreenGameWindowKey  = @"fullScreen";

#define MainMenu_Window_OpenEmuTag 501
@interface OEMainWindowController () <OELibraryControllerDelegate> {
    OEGameDocument *_documentForFullScreenWindow;
}
- (void)OE_replaceCurrentContentController:(NSViewController *)oldController withViewController:(NSViewController *)newController;
@end

@implementation OEMainWindowController
@synthesize currentContentController;
@synthesize defaultContentController;
@synthesize allowWindowResizing;
@synthesize libraryController;
@synthesize placeholderView;

- (void)dealloc 
{
    currentContentController = nil;
    [self setDefaultContentController:nil];
    [self setLibraryController:nil];
    [self setPlaceholderView:nil];
}

- (void)windowDidLoad
{
    [super windowDidLoad];
    
    [[self libraryController] setDelegate:self];
    [[self libraryController] setSidebarChangesWindowSize:YES];
    
    [self setAllowWindowResizing:YES];
    [[self window] setWindowController:self];
    [[self window] setDelegate:self];
    
    // Setup Window behavior
    [[self window] setRestorable:NO];
    [[self window] setExcludedFromWindowsMenu:YES];
    
    if(![[NSUserDefaults standardUserDefaults] boolForKey:OESetupAssistantHasFinishedKey])
    {
        OESetupAssistant *setupAssistant = [[OESetupAssistant alloc] init];
        [setupAssistant setCompletionBlock:
         ^(BOOL discoverRoms, NSArray* volumes)
         {
             if(discoverRoms)
                 [[[OELibraryDatabase defaultDatabase] importer] discoverRoms:volumes];
             [self setCurrentContentController:[self libraryController]];
         }];

        [[self window] center];

        [self setCurrentContentController:setupAssistant];
    }
    else
    {
        [self setCurrentContentController:[self libraryController]];
    }
}

- (NSString *)windowNibName
{
    return @"MainWindow";
}

- (void)openGameDocument:(OEGameDocument *)aDocument;
{
    NSUserDefaults *standardDefaults = [NSUserDefaults standardUserDefaults];
//    BOOL allowPopout = [standardDefaults boolForKey:OEAllowPopoutGameWindowKey];
    BOOL forcePopout = [standardDefaults boolForKey:OEForcePopoutGameWindowKey];
    BOOL fullScreen  = [standardDefaults boolForKey:OEFullScreenGameWindowKey];

//    BOOL usePopout = forcePopout || allowPopout;

    if(forcePopout)
    {
        [aDocument showInSeparateWindow:self fullScreen:fullScreen];
        [[aDocument gameViewController] playGame:self];
    }
    else
    {
        if(fullScreen && ![[self window] OE_isFullScreen])
        {
            _documentForFullScreenWindow = aDocument;
            [self OE_replaceCurrentContentController:[self currentContentController] withViewController:nil];
            [[self window] toggleFullScreen:self];
        }
        else
        {
            [self setCurrentContentController:[aDocument viewController]];
            [[aDocument gameViewController] playGame:self];
        }
    }
}

- (void)windowWillEnterFullScreen:(NSNotification *)notification
{
    [[self libraryController] setSidebarChangesWindowSize:NO];
}

- (void)windowDidEnterFullScreen:(NSNotification *)notification
{
    if(_documentForFullScreenWindow)
    {
        [self setCurrentContentController:[_documentForFullScreenWindow viewController]];
        [[_documentForFullScreenWindow gameViewController] playGame:self];
    }
}

- (void)windowDidExitFullScreen:(NSNotification *)notification
{
    [[self libraryController] setSidebarChangesWindowSize:YES];
}

#pragma mark -
- (void)OE_replaceCurrentContentController:(NSViewController *)oldController withViewController:(NSViewController *)newController
{     
    NSView *contentView = [self placeholderView];

    // final target
    [[newController view] setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [[newController view] setFrame:[contentView frame]];

    [oldController viewWillDisappear];
    [newController viewWillAppear];

    if(oldController != nil)
    {
        if(newController != nil)
        {
            [contentView replaceSubview:[oldController view] with:[newController view]];
        }
        else
        {
            [[oldController view] removeFromSuperview];
        }
    }
    else
    {
        if(newController != nil)
        {
            [contentView addSubview:[newController view]];
        }
    }

    [oldController viewDidDisappear];
    [newController viewDidAppear];

    if(newController)
    {
        [[self window] makeFirstResponder:[newController view]];
    }

    currentContentController = newController;
}

- (void)setCurrentContentController:(NSViewController *)controller
{
    if(controller == nil) controller = [self libraryController];

    if(controller == [self currentContentController]) return;

    NSBitmapImageRep *currentState = [[self placeholderView] fadeImage], *newState = nil;
    if([currentContentController respondsToSelector:@selector(setCachedSnapshot:)])
        [(id <OEMainWindowContentController>)currentContentController setCachedSnapshot:currentState];

    [currentContentController viewWillDisappear];
    [controller viewWillAppear];

    NSView *placeHolderView = [self placeholderView];
    OEFadeView *fadeView = [[OEFadeView alloc] initWithFrame:[placeHolderView bounds]];

    if(currentContentController)
        [placeholderView replaceSubview:[currentContentController view] with:fadeView];
    else
        [placeholderView addSubview:fadeView];

    if([controller respondsToSelector:@selector(cachedSnapshot)])
        newState = [(id <OEMainWindowContentController>)controller cachedSnapshot];

    [fadeView fadeFromImage:currentState toImage:newState callback:
     ^{
         [[controller view] setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
         [[controller view] setFrame:[placeHolderView frame]];

         [placeHolderView replaceSubview:fadeView with:[controller view]];

         [[self window] makeFirstResponder:[controller view]];

         [currentContentController viewDidDisappear];
         [controller viewDidAppear];
         currentContentController = controller;

         [fadeView removeFromSuperview];
     }];
}

#pragma mark -
#pragma mark OELibraryControllerDelegate protocol conformance
- (void)libraryController:(OELibraryController *)sender didSelectGame:(OEDBGame *)aGame
{
    NSError         *error = nil;
    OEDBSaveState   *state = [aGame autosaveForLastPlayedRom];
    OEGameDocument  *gameDocument = nil;

    if(state && [[OEHUDAlert loadAutoSaveGameAlert] runModal] == NSAlertDefaultReturn)
        gameDocument = [[OEGameDocument alloc] initWithSaveState:state error:&error];
    else
        gameDocument = [[OEGameDocument alloc] initWithGame:aGame error:&error];
    
    if(gameDocument == nil)
    {
        if(error!=nil)
            [NSApp presentError:error];
        return;
    }
    
    [[NSDocumentController sharedDocumentController] addDocument:gameDocument];
    [self openGameDocument:gameDocument];
}


- (void)libraryController:(OELibraryController *)sender didSelectSaveState:(OEDBSaveState *)aSaveState
{
    NSError        *error = nil;
    OEGameDocument *gameDocument = [[OEGameDocument alloc] initWithSaveState:aSaveState error:&error];
    
    if(gameDocument != nil)
    {
        [[NSDocumentController sharedDocumentController] addDocument:gameDocument];
        [self openGameDocument:gameDocument];
    }
    else if(error != nil) [NSApp presentError:error];
}

#pragma mark - OEGameViewControllerDelegate protocol conformance
- (void)emulationDidFinishForGameViewController:(id)sender
{
    if(_documentForFullScreenWindow)
    {
        _documentForFullScreenWindow = nil;
        if([[self window] OE_isFullScreen])
        {
            [[self window] toggleFullScreen:self];
        }
    }
}

- (void)emulationWillFinishForGameViewController:(OEGameViewController *)sender
{
    [self setCurrentContentController:nil];
}
#pragma mark -
#pragma mark NSWindow delegate
- (NSSize)windowWillResize:(NSWindow *)sender toSize:(NSSize)frameSize
{
    return [self allowWindowResizing] ? frameSize : [sender frame].size;
}

- (void)windowWillClose:(NSNotification *)notification
{
    [self setCurrentContentController:nil];
}


- (void)windowDidBecomeMain:(NSNotification *)notification
{
    NSMenu *mainMenu = [NSApp mainMenu];

    NSMenu *windowMenu = [[mainMenu itemAtIndex:5] submenu];
    NSMenuItem *item = [windowMenu itemWithTag:MainMenu_Window_OpenEmuTag];
    [item setState:NSOnState];
}

- (void)windowDidResignMain:(NSNotification *)notification
{
    NSMenu *mainMenu = [NSApp mainMenu];
    
    NSMenu *windowMenu = [[mainMenu itemAtIndex:5] submenu];
    NSMenuItem *item = [windowMenu itemWithTag:MainMenu_Window_OpenEmuTag];
    [item setState:NSOffState];
}
#pragma mark -
#pragma mark Menu Items
- (IBAction)showOpenEmuWindow:(id)sender;
{
    [self close];
}

- (IBAction)launchLastPlayedROM:(id)sender
{
    OEDBRom *rom = [sender representedObject];
    if(!rom) return;
    
    NSError        *error = nil;
    OEGameDocument *gameDocument = [[OEGameDocument alloc] initWithRom:rom error:&error];
    
    if(gameDocument != nil)
    {
        [[NSDocumentController sharedDocumentController] addDocument:gameDocument];
        [self openGameDocument:gameDocument];
    }
    else if(error != nil) [NSApp presentError:error];
}

@end
