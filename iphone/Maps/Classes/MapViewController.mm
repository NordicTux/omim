#import "MapViewController.h"
#import "SearchVC.h"
#import "MapsAppDelegate.h"
#import "EAGLView.h"
#import "BalloonView.h"
#import "BookmarksRootVC.h"
#import "PlacePageVC.h"
#import "../Settings/SettingsManager.h"
#import "../../Common/CustomAlertView.h"

#include "../../../gui/controller.hpp"

#include "RenderContext.hpp"


@implementation MapViewController

@synthesize m_myPositionButton;

//********************************************************************************************
//*********************** Callbacks from LocationManager *************************************
- (void) onLocationError:(location::TLocationError)errorCode
{
  GetFramework().OnLocationError(errorCode);
  switch (errorCode)
  {
    case location::EDenied:
    {
      UIAlertView * alert = [[CustomAlertView alloc] initWithTitle:nil
                                                       message:NSLocalizedString(@"location_is_disabled_long_text", @"Location services are disabled by user alert - message")
                                                      delegate:nil 
                                             cancelButtonTitle:NSLocalizedString(@"ok", @"Location Services are disabled by user alert - close alert button")
                                             otherButtonTitles:nil];
      [alert show];
      [alert release];
      [[MapsAppDelegate theApp].m_locationManager stop:self];
    }
    break;
    case location::ENotSupported:
    {
      UIAlertView * alert = [[CustomAlertView alloc] initWithTitle:nil
                                                       message:NSLocalizedString(@"device_doesnot_support_location_services", @"Location Services are not available on the device alert - message")
                                                      delegate:nil
                                             cancelButtonTitle:NSLocalizedString(@"ok", @"Location Services are not available on the device alert - close alert button")
                                             otherButtonTitles:nil];
      [alert show];
      [alert release];
      [[MapsAppDelegate theApp].m_locationManager stop:self];
    }
    break;
  default:
    break;
  }
}

- (void) onLocationUpdate:(location::GpsInfo const &)info
{
  if (GetFramework().GetLocationState()->IsFirstPosition())
  {
    [m_myPositionButton setImage:[UIImage imageNamed:@"location-selected.png"] forState:UIControlStateSelected];
  }
  
  GetFramework().OnLocationUpdate(info);
  [self updateDataAfterScreenChanged];
}

- (void) onCompassUpdate:(location::CompassInfo const &)info
{
  GetFramework().OnCompassUpdate(info);
}
//********************************************************************************************
//********************************************************************************************

- (IBAction)OnMyPositionClicked:(id)sender
{
  if (m_myPositionButton.isSelected == NO)
  {
    m_myPositionButton.selected = YES;
    [m_myPositionButton setImage:[UIImage imageNamed:@"location-search.png"] forState:UIControlStateSelected];
    GetFramework().StartLocation();
    [[MapsAppDelegate theApp] disableStandby];
    [[MapsAppDelegate theApp].m_locationManager start:self];
  }
  else
  {
    m_myPositionButton.selected = NO;
    [m_myPositionButton setImage:[UIImage imageNamed:@"location.png"] forState:UIControlStateSelected];
    GetFramework().StopLocation();
    [[MapsAppDelegate theApp] enableStandby];
    [[MapsAppDelegate theApp].m_locationManager stop:self];
  }
}

- (IBAction)OnSettingsClicked:(id)sender
{
  [[[MapsAppDelegate theApp] settingsManager] show:self];
}

- (IBAction)OnSearchClicked:(id)sender
{
  SearchVC * searchVC = [[SearchVC alloc] init];
  [self presentModalViewController:searchVC animated:YES];
  [searchVC release];
}

- (IBAction)OnBookmarksClicked:(id)sender
{
  BookmarksRootVC * bVC = [[BookmarksRootVC alloc] initWithBalloonView:m_balloonView];
  UINavigationController * navC = [[UINavigationController alloc] initWithRootViewController:bVC];
  [self presentModalViewController:navC animated:YES];
  [bVC release];
  [navC release];
}

- (void) onBalloonClicked
{
  PlacePageVC * placePageVC = [[PlacePageVC alloc] initWithBalloonView:m_balloonView];
  [self.navigationController pushViewController:placePageVC animated:YES];
  [placePageVC release];
}

- (CGPoint) viewPoint2GlobalPoint:(CGPoint)pt
{
  CGFloat const scaleFactor = self.view.contentScaleFactor;
  m2::PointD const ptG = GetFramework().PtoG(m2::PointD(pt.x * scaleFactor, pt.y * scaleFactor));
  return CGPointMake(ptG.x, ptG.y);
}

- (CGPoint) globalPoint2ViewPoint:(CGPoint)pt
{
  CGFloat const scaleFactor = self.view.contentScaleFactor;
  m2::PointD const ptP = GetFramework().GtoP(m2::PointD(pt.x, pt.y));
  return CGPointMake(ptP.x / scaleFactor, ptP.y / scaleFactor);
}


- (void) updatePinTexts:(Framework::AddressInfo const &)info
{
  NSString * res = [NSString stringWithUTF8String:info.m_name.c_str()];

  if (!info.m_types.empty())
  {
    NSString * type = [NSString stringWithUTF8String:info.m_types[0].c_str()];

    if (res.length == 0)
      res = [type capitalizedString];
    else
      res = [NSString stringWithFormat:@"%@ (%@)", res, type];
  }

  if (res.length == 0)
    res = NSLocalizedString(@"dropped_pin", nil);

  m_balloonView.title = res;
  //m_balloonView.description = [NSString stringWithUTF8String:info.FormatAddress().c_str()];
  //m_balloonView.type = [NSString stringWithUTF8String:info.FormatTypes().c_str()];
}


- (void) processMapClickAtPoint:(CGPoint)point longClick:(BOOL)isLongClick
{
  if (m_balloonView.isDisplayed)
  {
    [m_balloonView hide];
//    if (!isLongClick)
//      return;
  }

  // Try to check if we've clicked on bookmark
  Framework & f = GetFramework();
  CGFloat const scaleFactor = self.view.contentScaleFactor;
  // @TODO Refactor point transformation
  m2::PointD pxClicked(point.x * scaleFactor, point.y * scaleFactor);

  BookmarkAndCategory const bmAndCat = f.GetBookmark(pxClicked);
  if (IsValid(bmAndCat))
  {
    // Already added bookmark was clicked
    BookmarkCategory * cat = f.GetBmCategory(bmAndCat.first);
    if (cat)
    {
      // Automatically reveal hidden bookmark on a click
      if (!cat->IsVisible())
      {
        // Category visibility will be autosaved after editing bookmark
        cat->SetVisible(true);
        [self Invalidate];
      }

      Bookmark const * bm = cat->GetBookmark(bmAndCat.second);
      if (bm)
      {
        m2::PointD const globalPos = bm->GetOrg();
        // Set it before changing balloon title to display different images in case of creating/editing Bookmark
        m_balloonView.editedBookmark = bmAndCat;
        m_balloonView.globalPosition = CGPointMake(globalPos.x, globalPos.y);
        m_balloonView.title = [NSString stringWithUTF8String:bm->GetName().c_str()];
        m_balloonView.color = [NSString stringWithUTF8String:bm->GetType().c_str()];
        m_balloonView.setName = [NSString stringWithUTF8String:cat->GetName().c_str()];
        [m_balloonView showInView:self.view atPoint:[self globalPoint2ViewPoint:m_balloonView.globalPosition]];
      }
    }
  }
  else
  {
    // Check if we've clicked on visible POI
    Framework::AddressInfo addrInfo;
    m2::PointD pxPivot;
    if (f.GetVisiblePOI(pxClicked, pxPivot, addrInfo))
    {
      m2::PointD const gPivot = f.PtoG(pxPivot);
      m_balloonView.globalPosition = CGPointMake(gPivot.x, gPivot.y);
      [self updatePinTexts:addrInfo];
      [m_balloonView showInView:self.view atPoint:CGPointMake(pxPivot.x / scaleFactor, pxPivot.y / scaleFactor)];
    }
    else
    {
      // Just a click somewhere on a map
      if (isLongClick)
      {
        f.GetAddressInfo(pxClicked, addrInfo);
        // @TODO Refactor point transformation
        m_balloonView.globalPosition = [self viewPoint2GlobalPoint:point];
        [self updatePinTexts:addrInfo];
        [m_balloonView showInView:self.view atPoint:point];
      }
    }
  }
}

- (void)showSearchResultAsBookmarkAtMercatorPoint:(m2::PointD const &)pt withInfo:(Framework::AddressInfo const &)info
{
  m_balloonView.globalPosition = CGPointMake(pt.x, pt.y);
  [self updatePinTexts:info];
  [m_balloonView showInView:self.view atPoint:[self globalPoint2ViewPoint:m_balloonView.globalPosition]];
}

- (void) onSingleTap:(NSValue *)point
{
  [self processMapClickAtPoint:[point CGPointValue] longClick:NO];
}

- (void) onLongTap:(NSValue *)point
{
  [self processMapClickAtPoint:[point CGPointValue] longClick:YES];
}

- (void) dealloc
{
  [m_balloonView release];
  [super dealloc];
}

- (id) initWithCoder: (NSCoder *)coder
{
	if ((self = [super initWithCoder:coder]))
	{
    self.title = NSLocalizedString(@"back", @"Back button in nav bar to show the map");

    // Helper to display/hide pin on screen tap
    m_balloonView = [[BalloonView alloc] initWithTarget:self andSelector:@selector(onBalloonClicked)];

    /// @TODO refactor cyclic dependence.
    /// Here we're creating view and window handle in it, and later we should pass framework to the view.
    EAGLView * v = (EAGLView *)self.view;

    Framework & f = GetFramework();

    f.AddString("country_status_added_to_queue", [NSLocalizedString(@"country_status_added_to_queue", @"Message to display at the center of the screen when the country is added to the downloading queue") UTF8String]);
    f.AddString("country_status_downloading", [NSLocalizedString(@"country_status_downloading", @"Message to display at the center of the screen when the country is downloading") UTF8String]);
    f.AddString("country_status_download", [NSLocalizedString(@"country_status_download", @"Button text for the button at the center of the screen when the country is not downloaded") UTF8String]);
    f.AddString("country_status_download_failed", [NSLocalizedString(@"country_status_download_failed", @"Message to display at the center of the screen when the country download has failed") UTF8String]);
    f.AddString("try_again", [NSLocalizedString(@"try_again", @"Button text for the button under the country_status_download_failed message") UTF8String]);

		m_StickyThreshold = 10;

		m_CurrentAction = NOTHING;

    // restore previous screen position
    if (!f.LoadState())
      f.SetMaxWorldRect();

    [v initRenderPolicy];

    f.Invalidate();
	}

	return self;
}

NSInteger compareAddress(id l, id r, void * context)
{
	return l < r;
}

- (void) updatePointsFromEvent:(UIEvent*)event
{
	NSSet * allTouches = [event allTouches];

  UIView * v = self.view;
  CGFloat const scaleFactor = v.contentScaleFactor;

	if ([allTouches count] == 1)
	{
		CGPoint const pt = [[[allTouches allObjects] objectAtIndex:0] locationInView:v];
		m_Pt1 = m2::PointD(pt.x * scaleFactor, pt.y * scaleFactor);
	}
	else
	{
		NSArray * sortedTouches = [[allTouches allObjects] sortedArrayUsingFunction:compareAddress context:NULL];
		CGPoint const pt1 = [[sortedTouches objectAtIndex:0] locationInView:v];
		CGPoint const pt2 = [[sortedTouches objectAtIndex:1] locationInView:v];

		m_Pt1 = m2::PointD(pt1.x * scaleFactor, pt1.y * scaleFactor);
	  m_Pt2 = m2::PointD(pt2.x * scaleFactor, pt2.y * scaleFactor);
	}
}

- (void) updateDataAfterScreenChanged
{
  if (m_balloonView.isDisplayed)
    [m_balloonView updatePosition:self.view atPoint:[self globalPoint2ViewPoint:m_balloonView.globalPosition]];
}

- (void) stopCurrentAction
{
	switch (m_CurrentAction)
	{
		case NOTHING:
			break;
		case DRAGGING:
			GetFramework().StopDrag(DragEvent(m_Pt1.x, m_Pt1.y));
			break;
		case SCALING:
			GetFramework().StopScale(ScaleEvent(m_Pt1.x, m_Pt1.y, m_Pt2.x, m_Pt2.y));
			break;
	}

	m_CurrentAction = NOTHING;

  [self updateDataAfterScreenChanged];
}

- (void) touchesBegan:(NSSet*)touches withEvent:(UIEvent*)event
{
  // To cancel single tap timer
  UITouch * theTouch = (UITouch *)[touches anyObject];
  if (theTouch.tapCount > 1)
    [NSObject cancelPreviousPerformRequestsWithTarget:self];

	[self updatePointsFromEvent:event];

	if ([[event allTouches] count] == 1)
	{
    if (GetFramework().GetGuiController()->OnTapStarted(m_Pt1))
      return;
    
		GetFramework().StartDrag(DragEvent(m_Pt1.x, m_Pt1.y));
		m_CurrentAction = DRAGGING;

    // Start long-tap timer
    [self performSelector:@selector(onLongTap:) withObject:[NSValue valueWithCGPoint:[theTouch locationInView:self.view]] afterDelay:1.0];
    // Temporary solution to filter long touch
    m_touchDownPoint = m_Pt1;
	}
	else
	{
		GetFramework().StartScale(ScaleEvent(m_Pt1.x, m_Pt1.y, m_Pt2.x, m_Pt2.y));
		m_CurrentAction = SCALING;
	}

	m_isSticking = true;
}

- (void) touchesMoved:(NSSet*)touches withEvent:(UIEvent*)event
{
  m2::PointD const TempPt1 = m_Pt1;
	m2::PointD const TempPt2 = m_Pt2;

	[self updatePointsFromEvent:event];

  // Cancel long-touch timer
  if (!m_touchDownPoint.EqualDxDy(m_Pt1, 9))
    [NSObject cancelPreviousPerformRequestsWithTarget:self];

  if (GetFramework().GetGuiController()->OnTapMoved(m_Pt1))
    return;
  
	if (m_isSticking)
	{
		if ((TempPt1.Length(m_Pt1) > m_StickyThreshold) || (TempPt2.Length(m_Pt2) > m_StickyThreshold))
    {
			m_isSticking = false;
    }
		else
		{
			// Still stickying. Restoring old points and return.
			m_Pt1 = TempPt1;
			m_Pt2 = TempPt2;
			return;
		}
	}

	switch (m_CurrentAction)
	{
	case DRAGGING:
		GetFramework().DoDrag(DragEvent(m_Pt1.x, m_Pt1.y));
//		needRedraw = true;
		break;
	case SCALING:
		if ([[event allTouches] count] < 2)
			[self stopCurrentAction];
		else
		{
			GetFramework().DoScale(ScaleEvent(m_Pt1.x, m_Pt1.y, m_Pt2.x, m_Pt2.y));
//			needRedraw = true;
		}
		break;
	case NOTHING:
		return;
	}

  [self updateDataAfterScreenChanged];
}

- (void) touchesEnded:(NSSet*)touches withEvent:(UIEvent*)event
{
	[self updatePointsFromEvent:event];
	[self stopCurrentAction];

  UITouch * theTouch = (UITouch*)[touches anyObject];
  int tapCount = theTouch.tapCount;
  int touchesCount = [[event allTouches] count];

  Framework & f = GetFramework();
  if (touchesCount == 1)
  {
    // Cancel long-touch timer
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    if (tapCount == 1)
    {
      if (f.GetGuiController()->OnTapEnded(m_Pt1))
        return;

      // Launch single tap timer
      if (m_isSticking)
        [self performSelector:@selector(onSingleTap:) withObject:[NSValue valueWithCGPoint:[theTouch locationInView:self.view]] afterDelay:0.3];
    }
    else if (tapCount == 2 && m_isSticking)
      f.ScaleToPoint(ScaleToPointEvent(m_Pt1.x, m_Pt1.y, 2.0));
  }

  if (touchesCount == 2 && tapCount == 1 && m_isSticking)
    f.Scale(0.5);

  [self updateDataAfterScreenChanged];
}

- (void) touchesCancelled:(NSSet*)touches withEvent:(UIEvent*)event
{
	[self updatePointsFromEvent:event];
	[self stopCurrentAction];
}

- (BOOL) shouldAutorotateToInterfaceOrientation: (UIInterfaceOrientation) interfaceOrientation
{
	return YES; // We support all orientations
}

- (void) didReceiveMemoryWarning
{
	GetFramework().MemoryWarning();
  [super didReceiveMemoryWarning];
}

- (void) viewDidUnload
{
  // to correctly release view on memory warnings
  self.m_myPositionButton = nil;
  [super viewDidUnload];
}

- (void) OnTerminate
{
  GetFramework().SaveState();
}

- (void) Invalidate
{
  Framework & f = GetFramework();
  if (!f.SetUpdatesEnabled(true))
    f.Invalidate();
}

- (void) didRotateFromInterfaceOrientation: (UIInterfaceOrientation) fromInterfaceOrientation
{
  [[MapsAppDelegate theApp].m_locationManager setOrientation:self.interfaceOrientation];
  // Update popup bookmark position
  [self updateDataAfterScreenChanged];
  [self Invalidate];
}

- (void) OnEnterBackground
{
  // save world rect for next launch
  Framework & f = GetFramework();
  f.SaveState();
  f.SetUpdatesEnabled(false);
  f.EnterBackground();
}

- (void) OnEnterForeground
{
  GetFramework().EnterForeground();
  if (self.isViewLoaded && self.view.window)
    [self Invalidate]; // only invalidate when map is displayed on the screen
}

- (void) viewWillAppear:(BOOL)animated
{
  [self Invalidate];
  // Update popup bookmark position
  [self updateDataAfterScreenChanged];
  [super viewWillAppear:animated];
}

- (void) viewWillDisappear:(BOOL)animated
{
  GetFramework().SetUpdatesEnabled(false);
  [super viewWillDisappear:animated];
}

- (void) SetupMeasurementSystem
{
  GetFramework().SetupMeasurementSystem();
}

-(BOOL) OnProcessURL:(NSString*)url
{
  GetFramework().SetViewportByURL([url UTF8String]);
  return TRUE;
}

@end
