import { BaseConstants, Logger } from '@ohos/base';
import { downloadMediaFromMessage, MediaType } from '../../api';
import { MessageDataSource } from '../../viewmodel/Message/MessageDataSource';
import { fileIo as fs } from '@kit.CoreFileKit';
import { HashMap } from '@kit.ArkTS';
import { deviceInfo } from '@kit.BasicServicesKit';

export class MediaViewerParams {
  chatId: string = '';
  messageId: number = -1;

  constructor(chatId: string, messageId: number) {
    this.chatId = chatId;
    this.messageId = messageId;
  }
}

export let isMediaViewerOpening: boolean = false;
export function setMediaViewerOpening(opening: boolean): void {
  isMediaViewerOpening = opening;
}

export const mediaDownloadPromises: HashMap<string, Promise<string>> = new HashMap<string, Promise<string>>();

const MEDIA_DOWNLOAD_TIMEOUT_MS: number = 45000;

export function withMediaDownloadTimeout(promise: Promise<string>, mediaPath: string): Promise<string> {
  let timerId: number = -1;
  const timeoutPromise = new Promise<string>((_, reject) => {
    timerId = setTimeout(() => {
      if (mediaDownloadPromises.hasKey(mediaPath)) {
        mediaDownloadPromises.remove(mediaPath);
      }
      reject(new Error('Media download timed out'));
    }, MEDIA_DOWNLOAD_TIMEOUT_MS);
  });
  return Promise.race([
    promise.then((res: string) => {
      clearTimeout(timerId);
      return res;
    }).catch((err: Error) => {
      clearTimeout(timerId);
      throw err;
    }),
    timeoutPromise
  ]);
}

@Component
export struct MediaViewer {
  @Consume('pageInfo') pageInfo: NavPathStack;
  @Consume messagesOfChatMap: HashMap<string, MessageDataSource>;
  @State mediaViewerChatId: string = '';
  @State mediaViewerMessageId: number = -1;
  @State mediaPath: string = '';
  @State mediaLoaded: boolean = false;
  @State mediaLoadFailed: boolean = false;
  @State isPhoto: boolean = true;
  @State imageScale: number = 1;
  @State offsetX: number = 0;
  @State offsetY: number = 0;
  @State viewerWidth: number = 0;
  @State viewerHeight: number = 0;
  @State retryCount: number = 0;
  private maxRetries: number = 3;
  private baseScale: number = 1;
  private baseOffsetX: number = 0;
  private baseOffsetY: number = 0;
  private lastPanX: number = 0;
  private lastPanY: number = 0;
  private loadToken: number = 0;

  private clampPan(): void {
    // Approximation: uses viewer bounds, not the displayed Contain image size,
    // so letterbox space is included in the pan range.
    const maxOffsetX = Math.max(0, this.viewerWidth * (this.imageScale - 1) / 2);
    const maxOffsetY = Math.max(0, this.viewerHeight * (this.imageScale - 1) / 2);
    this.offsetX = Math.min(Math.max(this.offsetX, -maxOffsetX), maxOffsetX);
    this.offsetY = Math.min(Math.max(this.offsetY, -maxOffsetY), maxOffsetY);
  }

  private resetZoom(): void {
    this.imageScale = 1;
    this.offsetX = 0;
    this.offsetY = 0;
    this.baseScale = 1;
    this.baseOffsetX = 0;
    this.baseOffsetY = 0;
    this.lastPanX = 0;
    this.lastPanY = 0;
  }

  private checkIfPhoto(): boolean {
    if (this.messagesOfChatMap && this.mediaViewerChatId) {
      const ds = this.messagesOfChatMap.get(this.mediaViewerChatId);
      if (ds && this.mediaViewerMessageId > 0) {
        const msg = ds.getMessageById(this.mediaViewerMessageId);
        if (msg) {
          return msg.mediaType === MediaType.Photo;
        }
      }
    }
    return true; // unknown / missing message defaults to "photo" attempt
  }

  loadMedia(forceDownload: boolean = false): void {
    let loadToken = ++this.loadToken;
    this.resetZoom();

    if (!this.checkIfPhoto()) {
      this.isPhoto = false;
      this.mediaLoaded = false;
      this.mediaLoadFailed = false;
      return;
    }
    this.isPhoto = true;
    this.mediaLoaded = false;
    this.mediaLoadFailed = false;

    if (!this.mediaViewerChatId || this.mediaViewerMessageId <= 0) {
      Logger.error('MediaViewer: invalid chatId or messageId: ' + this.mediaViewerChatId + ', ' + this.mediaViewerMessageId);
      this.mediaLoadFailed = true;
      return;
    }
    const chatIdNum = Number(this.mediaViewerChatId);
    if (!Number.isFinite(chatIdNum) || chatIdNum === 0) {
      Logger.error('MediaViewer: invalid numeric chatId: ' + this.mediaViewerChatId);
      this.mediaLoadFailed = true;
      return;
    }
    const messageIdNum = this.mediaViewerMessageId;
    this.mediaPath = BaseConstants.BASE_DIR + this.mediaViewerChatId + "/" + this.mediaViewerMessageId + ".jpg";

    let downloadPromise: Promise<string> | undefined = forceDownload ? undefined : mediaDownloadPromises.get(this.mediaPath);
    if (downloadPromise) {
      withMediaDownloadTimeout(downloadPromise, this.mediaPath)
        .then((path: string) => {
          if (loadToken !== this.loadToken) {
            return;
          }
          this.mediaPath = path;
          this.mediaLoaded = true;
          this.mediaLoadFailed = false;
        })
        .catch((error: Error) => {
          if (loadToken !== this.loadToken) {
            return;
          }
          Logger.error('MediaViewer: in-flight download failed: ' + error.message);
          this.mediaLoadFailed = true;
        });
      return;
    }

    let exists = false;
    try {
      exists = fs.accessSync(this.mediaPath);
    } catch (e) {
      exists = false;
    }
    if (exists && !forceDownload) {
      this.mediaLoaded = true;
      this.mediaLoadFailed = false;
      return;
    }

    const rawPromise = downloadMediaFromMessage(chatIdNum, messageIdNum);
    const timedPromise = withMediaDownloadTimeout(rawPromise, this.mediaPath);
    mediaDownloadPromises.set(this.mediaPath, timedPromise);

    timedPromise
      .then((path: string) => {
        if (mediaDownloadPromises.hasKey(this.mediaPath) && mediaDownloadPromises.get(this.mediaPath) === timedPromise) {
          mediaDownloadPromises.remove(this.mediaPath);
        }
        if (loadToken !== this.loadToken) {
          return;
        }
        this.mediaPath = path;
        this.mediaLoaded = true;
        this.mediaLoadFailed = false;
      })
      .catch((error: Error) => {
        if (mediaDownloadPromises.hasKey(this.mediaPath) && mediaDownloadPromises.get(this.mediaPath) === timedPromise) {
          mediaDownloadPromises.remove(this.mediaPath);
        }
        if (loadToken !== this.loadToken) {
          return;
        }
        Logger.error('MediaViewer: download failed: ' + error.message);
        this.mediaLoadFailed = true;
      });
  }

  aboutToAppear(): void {
    this.resetZoom();
  }

  aboutToDisappear(): void {
    setMediaViewerOpening(false);
    this.loadToken++;
  }

  private closeViewer(): void {
    setMediaViewerOpening(false);
    this.loadToken++;
    this.pageInfo.pop();
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        if (!this.isPhoto) {
          Column({ space: 16 }) {
            Image($r('app.media.ic_public_video'))
              .width(64)
              .height(64)
              .fillColor('#88FFFFFF')
            Text('Media preview not supported')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
            Text('Video and non-photo media viewing are currently not supported.')
              .fontSize(14)
              .fontColor('#88FFFFFF')
              .textAlign(TextAlign.Center)
              .margin({ left: 32, right: 32 })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else {
          Stack() {
            if (this.mediaLoaded) {
              Image("file://" + this.mediaPath)
                .width('100%')
                .height('100%')
                .objectFit(ImageFit.Contain)
                .scale({ x: this.imageScale, y: this.imageScale })
                .translate({ x: this.offsetX, y: this.offsetY })
                .onError(() => {
                  Logger.error('MediaViewer: Image onError for ' + this.mediaPath);
                  this.mediaLoaded = false;
                  this.mediaLoadFailed = true;
                })
            } else if (this.mediaLoadFailed) {
              Column({ space: 12 }) {
                Text(this.retryCount >= this.maxRetries ? 'Unable to load media' : 'Failed to load image')
                  .fontColor('#AAFFFFFF')
                  .fontSize(14)
                if (this.retryCount < this.maxRetries) {
                  Text('Retry')
                    .fontColor(Color.Red)
                    .fontSize(16)
                    .fontWeight(FontWeight.Bold)
                    .onClick(() => {
                      this.retryCount++;
                      if (mediaDownloadPromises.hasKey(this.mediaPath)) {
                        mediaDownloadPromises.remove(this.mediaPath);
                      }
                      this.loadMedia(true);
                    })
                }
              }
            } else {
              LoadingProgress()
                .width(50)
                .height(50)
                .color(Color.White)
            }
          }
          .width('100%')
          .height('100%')
          .onAreaChange((_oldValue: Area, newValue: Area) => {
            this.viewerWidth = Number.parseFloat(newValue.width.toString());
            this.viewerHeight = Number.parseFloat(newValue.height.toString());
            this.clampPan();
          })
          .gesture(
            GestureGroup(GestureMode.Parallel,
              PinchGesture({ fingers: 2 })
                .onActionStart((_event: GestureEvent) => {
                  this.baseScale = this.imageScale;
                })
                .onActionUpdate((event: GestureEvent) => {
                  if (event) {
                    let oldScale = this.imageScale;
                    let nextScale = this.baseScale * event.scale;
                    if (!Number.isFinite(nextScale)) {
                      return;
                    }
                    if (nextScale < 1) {
                      nextScale = 1;
                    } else if (nextScale > 4) {
                      nextScale = 4;
                    }
                    // NOTE: pinchCenter origin (component-local vs screen coordinates) is UNVERIFIED on device.
                    // If coordinates are screen-based on device, subtract Stack global position.
                    // Device test is REQUIRED before assuming this formula works as expected.
                    if (oldScale > 0 && Number.isFinite(oldScale) && this.viewerWidth > 0 &&
                        this.viewerHeight > 0 && Number.isFinite(event.pinchCenterX) &&
                        Number.isFinite(event.pinchCenterY)) {
                      let ratio = nextScale / oldScale;
                      let cx = event.pinchCenterX - this.viewerWidth / 2;
                      let cy = event.pinchCenterY - this.viewerHeight / 2;
                      this.offsetX = cx * (1 - ratio) + this.offsetX * ratio;
                      this.offsetY = cy * (1 - ratio) + this.offsetY * ratio;
                    }
                    this.imageScale = nextScale;
                    this.clampPan();
                  }
                })
                .onActionEnd(() => {
                  if (this.imageScale <= 1) {
                    this.imageScale = 1;
                    this.offsetX = 0;
                    this.offsetY = 0;
                  }
                }),
              PanGesture()
                .onActionStart(() => {
                  this.lastPanX = 0;
                  this.lastPanY = 0;
                })
                .onActionUpdate((event: GestureEvent) => {
                  if (event) {
                    const dx = event.offsetX - this.lastPanX;
                    const dy = event.offsetY - this.lastPanY;
                    this.lastPanX = event.offsetX;
                    this.lastPanY = event.offsetY;
                    if (this.imageScale > 1 && Number.isFinite(dx) && Number.isFinite(dy)) {
                      this.offsetX += dx;
                      this.offsetY += dy;
                      this.clampPan();
                    }
                  }
                })
                .onActionEnd(() => {
                  if (this.imageScale <= 1) {
                    this.offsetX = 0;
                    this.offsetY = 0;
                  }
                }),
              TapGesture({ count: 2 })
                .onAction(() => {
                  if (this.imageScale > 1) {
                    this.resetZoom();
                  } else {
                    this.imageScale = 2;
                    this.clampPan();
                  }
                })
            )
          )
        }

        Row() {
          Button() {
            Image($r('app.media.ic_public_back'))
              .width(22)
              .height(22)
              .fillColor(Color.White)
          }
          .width(40)
          .height(40)
          .backgroundColor('#66000000')
          .borderRadius(20)
          .onClick(() => {
            this.closeViewer();
          })

          Blank()

          Button() {
            Image($r('app.media.ic_public_cancel'))
              .width(20)
              .height(20)
              .fillColor(Color.White)
          }
          .width(40)
          .height(40)
          .backgroundColor('#66000000')
          .borderRadius(20)
          .onClick(() => {
            this.closeViewer();
          })
        }
        .width('100%')
        .padding({
          left: 16,
          right: 16,
          bottom: 16,
          top: deviceInfo.deviceType === BaseConstants.DEVICE_2IN1 ? 16 : $r('app.float.device_padding_top')
        })
        .zIndex(10)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Black)
    }
    .hideTitleBar(true)
    .backgroundColor(Color.Black)
    .expandSafeArea([SafeAreaType.SYSTEM])
    .onBackPressed(() => {
      this.closeViewer();
      return true;
    })
    .onReady((context: NavDestinationContext) => {
      const param = context.pathInfo.param as MediaViewerParams;
      if (param) {
        this.mediaViewerChatId = param.chatId;
        this.mediaViewerMessageId = param.messageId;
      }
      this.retryCount = 0;
      this.loadMedia();
    })
  }
}
