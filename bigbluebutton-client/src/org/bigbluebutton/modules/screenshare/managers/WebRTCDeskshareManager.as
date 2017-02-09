/**
* BigBlueButton open source conferencing system - http://www.bigbluebutton.org/
*
* Copyright (c) 2015 BigBlueButton Inc. and by respective authors (see below).
*
* This program is free software; you can redistribute it and/or modify it under the
* terms of the GNU Lesser General Public License as published by the Free Software
* Foundation; either version 3.0 of the License, or (at your option) any later
* version.
*
* BigBlueButton is distributed in the hope that it will be useful, but WITHOUT ANY
* WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
* PARTICULAR PURPOSE. See the GNU Lesser General Public License for more details.
*
* You should have received a copy of the GNU Lesser General Public License along
* with BigBlueButton; if not, see <http://www.gnu.org/licenses/>.
*
*/

package org.bigbluebutton.modules.screenshare.managers
{
	import com.asfusion.mate.events.Dispatcher;

	import flash.external.ExternalInterface;

	import org.as3commons.logging.api.ILogger;
	import org.as3commons.logging.api.getClassLogger;
	import org.bigbluebutton.core.UsersUtil;
	import org.bigbluebutton.core.managers.UserManager;
	import org.bigbluebutton.main.events.MadePresenterEvent;
	import org.bigbluebutton.modules.screenshare.events.UseJavaModeCommand;
	import org.bigbluebutton.modules.screenshare.events.WebRTCViewStreamEvent;
	import org.bigbluebutton.modules.screenshare.model.ScreenshareOptions;
	import org.bigbluebutton.modules.screenshare.events.ShareWindowEvent;
	import org.bigbluebutton.modules.screenshare.events.WebRTCPublishWindowChangeState;
	import org.bigbluebutton.modules.screenshare.view.components.WebRTCDesktopPublishWindow;
	import org.bigbluebutton.modules.screenshare.services.WebRTCDeskshareService;
	import org.bigbluebutton.modules.screenshare.utils.BrowserCheck;
	import org.bigbluebutton.modules.screenshare.events.DeskshareToolbarEvent;
	import org.bigbluebutton.main.api.JSLog;

	public class WebRTCDeskshareManager {
		private static const LOGGER:ILogger = getClassLogger(WebRTCDeskshareManager);

		private var publishWindowManager:WebRTCPublishWindowManager;
		private var viewWindowManager:WebRTCViewerWindowManager;
		private var toolbarButtonManager:ToolbarButtonManager;
		private var module:ScreenshareModule;
		private var service:WebRTCDeskshareService;
		private var globalDispatcher:Dispatcher;
		private var sharing:Boolean = false;
		private var usingWebRTC:Boolean = false;
		private var chromeExtensionKey:String = null;

		public function WebRTCDeskshareManager() {
			JSLog.warn("WebRTCDeskshareManager::WebRTCDeskshareManager", {});
			service = new WebRTCDeskshareService();
			globalDispatcher = new Dispatcher();
			publishWindowManager = new WebRTCPublishWindowManager(service);
			viewWindowManager = new WebRTCViewerWindowManager(service);
		}

		public function handleStartModuleEvent(module:ScreenshareModule):void {
			LOGGER.debug("WebRTC Screenshare Module starting");
			JSLog.warn("WebRTCDeskshareManager::handleStartModuleEvent", {});
			this.module = module;
			service.handleStartModuleEvent(module);

			if (UsersUtil.amIPresenter()) {
				initDeskshare();
			}
		}

		public function handleStopModuleEvent():void {
			LOGGER.debug("WebRTC Deskshare Module stopping");

			publishWindowManager.stopSharing();
			viewWindowManager.stopViewing();
			service.disconnect();
		}

		/*presenter stopped their program stream*/
		public function handleStreamStoppedEvent():void {
			LOGGER.debug("WebRTCDeskshareManager::handleStreamStoppedEvent Sending deskshare stopped command");
			JSLog.warn("WebRTCDeskshareManager::handleStreamStoppedEvent", {});
			stopWebRTCDeskshare();
		}

		/*viewer being told there is no more stream*/
		public function handleStreamStopEvent(args:Object):void {
			LOGGER.debug("WebRTCDeskshareManager::handleStreamStopEvent");
			sharing = false;
			JSLog.warn("WebRTCDeskshareManager::handleStreamStopEvent", {});
			viewWindowManager.handleViewWindowCloseEvent();
		}

		public function handleRequestStopSharingEvent():void {
			JSLog.warn("WebRTCDeskshareManager::handleRequestStopSharingEvent", {});
			/* stopping WebRTC deskshare. Alert DeskshareManager to reset toolbar */
			globalDispatcher.dispatchEvent(new DeskshareToolbarEvent(DeskshareToolbarEvent.STOP));
			stopWebRTCDeskshare();
		}

		private function stopWebRTCDeskshare():void {
			LOGGER.debug("WebRTCDeskshareManager::stopWebRTCDeskshare");
			JSLog.warn("WebRTCDeskshareManager::stopWebRTCDeskshare", {});
			viewWindowManager.stopViewing();

			/* close the sharing window. The sharing window can also be open when going through
			extension installation */
			publishWindowManager.stopSharing();

			if (ExternalInterface.available) {
				ExternalInterface.call("vertoExitScreenShare");
			}
		}

		private function startWebRTCDeskshare():void {
			LOGGER.debug("WebRTCDeskshareManager::startWebRTCDeskshare");
			JSLog.warn("WebRTCDeskshareManager::startWebRTCDeskshare", {});

			if (ExternalInterface.available) {
				var videoTag:String = "localVertoVideo";
				var onFail:Function = function(args:Object):void {
					JSLog.warn("onFail - as", args);
					JSLog.warn("WebRTCDeskshareManager::startWebRTCDeskshare - falling back to java", {});
					globalDispatcher.dispatchEvent(new UseJavaModeCommand())
				};
				ExternalInterface.addCallback("onFail", onFail);

				var voiceBridge:String = UserManager.getInstance().getConference().voiceBridge;
				var myName:String = UserManager.getInstance().getConference().getMyName();

				ExternalInterface.call(
					'vertoShareScreen',
					videoTag,
					voiceBridge,
					myName,
					null,
					"onFail",
					chromeExtensionKey
				);
			}
		}

		private function initDeskshare():void {
			JSLog.warn("WebRTCDeskshareManager::initDeskshare", {});
			sharing = false;
			var options:ScreenshareOptions = new ScreenshareOptions();
			options.parseOptions();
			if (options.chromeExtensionKey) {
				chromeExtensionKey = options.chromeExtensionKey;
			}
		}

		public function handleMadePresenterEvent(e:MadePresenterEvent):void {
			LOGGER.debug("Got MadePresenterEvent ");
			initDeskshare();
		}

		public function handleMadeViewerEvent(e:MadePresenterEvent):void{
			LOGGER.debug("Got MadeViewerEvent ");
			if (sharing) {
				publishWindowManager.stopSharing();
				stopWebRTCDeskshare();
			}
			sharing = false;
		}

		private function canIUseVertoOnThisBrowser(newOnWebRTCBrokeFailure:Function = null, newOnNoWebRTCFailure:Function = null, newOnSuccess:Function = null):void {
			LOGGER.debug("DeskshareManager::canIUseVertoOnThisBrowser");
			JSLog.warn("WebRTCDeskshareManager::canIUseVertoOnThisBrowser", {});
			var options:ScreenshareOptions = new ScreenshareOptions();
			options.parseOptions();
			var onNoWebRTCFailure:Function, onWebRTCBrokeFailure:Function, onSuccess:Function;

			onNoWebRTCFailure = (newOnNoWebRTCFailure != null) ? newOnNoWebRTCFailure : function(message:String):void {
				JSLog.warn(message, {});
				usingWebRTC = false;
				// send out event to fallback to Java
				JSLog.warn("WebRTCDeskshareManager::handleStartSharingEvent - falling back to java", {});
				globalDispatcher.dispatchEvent(new UseJavaModeCommand());
				return;
			};

			onWebRTCBrokeFailure = (newOnWebRTCBrokeFailure != null) ? newOnWebRTCBrokeFailure : function(message:String):void {
				JSLog.warn(message, {});
				publishWindowManager.openWindow();
				globalDispatcher.dispatchEvent(new WebRTCPublishWindowChangeState(WebRTCPublishWindowChangeState.DISPLAY_INSTALL));
			};

			onSuccess = (newOnSuccess != null) ? newOnSuccess : function(message:String):void {
				JSLog.warn("WebRTCDeskshareManager::handleStartSharingEvent onSuccess", message);
				usingWebRTC = true;
				startWebRTCDeskshare();
			};

			if (options.tryWebRTCFirst && BrowserCheck.isWebRTCSupported()) {
				JSLog.warn("WebRTCDeskshareManager::handleStartSharingEvent WebRTC Supported", {});
				if (BrowserCheck.isFirefox()) {
					onSuccess("Firefox, lets try");
				} else {
					if (chromeExtensionKey != null) {

						JSLog.warn("WebRTCDeskshareManager::handleStartSharingEvent chrome extension link exists - ", chromeExtensionKey);
						if (ExternalInterface.available) {

							var success2:Function = function(exists:Boolean):void {
								ExternalInterface.addCallback("success2", null);
								JSLog.warn("WebRTCDeskshareManager::handleStartSharingEvent inside onSuccess2", {});
								if (exists) {
									JSLog.warn("Chrome Extension exists", {});
									onSuccess("worked");
								} else {
									onWebRTCBrokeFailure("No Chrome Extension");
									JSLog.warn("no chrome extension", {});
								}
							};
							ExternalInterface.addCallback("success2", success2);
							ExternalInterface.call("checkChromeExtInstalled", "success2", chromeExtensionKey);
						}
					} else {
						onNoWebRTCFailure("No chromeExtensionKey in config.xml");
						return;
					}
				}
			} else {
				onNoWebRTCFailure("Web browser doesn't support WebRTC");
				return;
			}
		}

		/*handle start sharing event*/
		public function handleStartSharingEvent():void {
			LOGGER.debug("WebRTCDeskshareManager::handleStartSharingEvent");
			JSLog.warn("WebRTCDeskshareManager::handleStartSharingEvent", {});
			canIUseVertoOnThisBrowser();
		}

		public function handleShareWindowCloseEvent():void {
			publishWindowManager.handleShareWindowCloseEvent();
			sharing = false;
			stopWebRTCDeskshare();
		}

		public function handleViewWindowCloseEvent():void {
			LOGGER.debug("Received stop viewing command");
			JSLog.warn("WebRTCDeskshareManager::handleViewWindowCloseEvent", {});
			sharing = false;
			viewWindowManager.handleViewWindowCloseEvent();
		}

		public function handleStreamStartEvent(e:WebRTCViewStreamEvent):void{
			JSLog.warn("WebRTCDeskshareManager::handleStreamStartEvent rtmp=", e.rtmp);
			// if (!usingWebRTC) { return; } //TODO this was causing issues
			if (sharing) return; //TODO must uncomment this for the non-webrtc desktop share
			JSLog.warn("WebRTCDeskshareManager::handleStreamStartEvent after sharing return", {});
			var isPresenter:Boolean = UserManager.getInstance().getConference().amIPresenter;
			JSLog.warn("WebRTCDeskshareManager::handleStreamStartEvent isPresenter=", isPresenter);
			LOGGER.debug("Received start viewing command when isPresenter==[{0}]",[isPresenter]);

			if(isPresenter) {
				JSLog.warn("WebRTCDeskshareManager::handleStreamStartEvent is presenter", {});
				publishWindowManager.startViewing(e.rtmp, e.videoWidth, e.videoHeight);
			} else {
				JSLog.warn("WebRTCDeskshareManager::handleStreamStartEvent is viewer", {});
				viewWindowManager.startViewing(e.rtmp, e.videoWidth, e.videoHeight);
			}

			 sharing = true; //TODO must uncomment this for the non-webrtc desktop share
		}

		public function handleUseJavaModeCommand():void {
			JSLog.warn("WebRTCDeskshareManager::handleUseJavaModeCommand", {});
			usingWebRTC = false;
		}

		public function handleRequestStartSharingEvent():void {
			JSLog.warn("WebRTCDeskshareManager::handleRequestStartSharingEvent", {});
			initDeskshare();
			handleStartSharingEvent();
		}

		public function handleScreenShareStartedEvent(event: WebRTCViewStreamEvent):void {
			if (UsersUtil.amIPresenter()) {
			} else {
				/*handleStreamStartEvent(ScreenshareModel.getInstance().streamId, event.width, event.height);*/
				handleStreamStartEvent(null);
			}

			var dispatcher:Dispatcher = new Dispatcher();
			dispatcher.dispatchEvent(new WebRTCViewStreamEvent(WebRTCViewStreamEvent.START));
		}
		
		/*public function handleIsSharingScreenEvent(event: IsSharingScreenEvent):void {*/
		public function handleIsSharingScreenEvent():void {
			if (UsersUtil.amIPresenter()) {
			} else {
				/*handleStreamStartEvent(ScreenshareModel.getInstance().streamId, event.width, event.height);*/
				handleStreamStartEvent(null);
			}

			var dispatcher:Dispatcher = new Dispatcher();
			dispatcher.dispatchEvent(new WebRTCViewStreamEvent(WebRTCViewStreamEvent.START));
		}
	}
}
