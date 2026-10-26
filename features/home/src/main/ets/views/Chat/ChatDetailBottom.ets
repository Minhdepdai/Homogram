/*
 * Copyright (c) 2023 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { BaseConstants } from '@ohos/base/src/main/ets/constants/BaseConstants';
import { StandardIcon } from '@ohos/base/src/main/ets/views/image/StandardIcon';
import { HomeConstants } from '../../constants/HomeConstants';
import { NativeMessage, sendMessage } from '../../api'
import { Logger } from '@ohos/base';
import { Chat } from '../../entities/Chat';
import { Message } from '../../entities/Message';
import { ChatDetailBottomPhotoPicker } from './ChatDetailBottomPhotoPicker';
import { ChatDetailBottomMediaSheet } from './ChatDetailBottomMediaSheet';
import { ReplyToPreview } from '../Message/ReplyToPreview';
import { curves } from '@kit.ArkUI';
import { HashMap } from '@kit.ArkTS';
import { ChatDataSource } from '../../viewmodel/Chat/ChatDataSource';
import { MessageDataSource } from '../../viewmodel/Message/MessageDataSource';

const MAX_BLUR_RADIUS = 20;

@AnimatableExtend(Tabs)
  function animatableBarHeight(height: number | string) {
  .barHeight(height)
}

@Component
export struct ChatDetailBottom {
  @State text: string = "";
  @Consume('pageInfo') pageInfo: NavPathStack;
  // @Consume pinnedChatsMap: HashMap<string, Chat>;
  // @Consume chatsMap: Map<string, Chat>;
  @Consume chatDataSource: ChatDataSource;
  @Consume messagesOfChatMap: HashMap<string, MessageDataSource>;
  @Consume discreteChatDetailBlurRadius: number;
  @Consume continuousChatDetailBlurRadius: number;
  @State animate: boolean = false;
  @State shouldShowGrid: boolean = false;
  @Link isShowMediaSheet: boolean;
  @State isShowMediaBarSheet: boolean = false;
  @State selectedMediaCount: number = 0;
  @State currentDetents: number = 0; // 0 means medium, 1 means full
  @State mediaSheetTitle: Resource = $r('app.string.gallery');
  @State @Watch('onSelectedMediasChanged') selectedMedias: Array<string> = [];
  @Consume @Watch('onCurrentChatIdChanged') currentChatId: string;
  @Link replyToMessageId: number | undefined;
  @State @Watch('onShouldSendMessageChanged') shouldSendMessage: boolean = false;
  @State isSending: boolean = false;
  private inFlightUris: Set<string> = new Set<string>();
  private deselectedDuringSend: Set<string> = new Set<string>();
  private sendEpoch: number = 0;

  onShouldSendMessageChanged(): void {
    if (this.shouldSendMessage) {
      this.shouldSendMessage = false;
      this.sendMessage();
    }
  }

  onSelectedMediasChanged(): void {
    if (!this.isSending) {
      return;
    }
    this.inFlightUris.forEach((uri: string) => {
      if (!this.selectedMedias.includes(uri)) {
        this.deselectedDuringSend.add(uri);
      }
    });
  }

  private onCurrentChatIdChanged(): void {
    this.sendEpoch++;
    this.replyToMessageId = undefined;
    this.text = "";
    this.isSending = false;
    this.clearSendTracking();
    this.selectedMedias = [];
    this.selectedMediaCount = 0;
  }

  private clearSendTracking(): void {
    this.inFlightUris.clear();
    this.deselectedDuringSend.clear();
  }

  @Builder
  MediaTab() {

  }

  @Builder
  SendMsgBtn() {
    Column() {
      Button() {
        SymbolGlyph($r('sys.symbol.paperplane_right_fill'))
          .fontSize(32)
          .renderingStrategy(SymbolRenderingStrategy.SINGLE)
          .fontColor([$r('sys.color.ohos_id_color_text_primary')])
      }
        .backgroundColor(Color.Transparent)
        .width(36)
        .height(36)
        .onClick(() => {
          try {
            this.sendMessage();
            Logger.debug("sendMessage: " + this.text);
          } catch (e) {
            Logger.error("sendMessage error: " + e.message);
          }
        })
    }
  }

  @Builder
  MediaSheet() {
    Flex({ direction: FlexDirection.Column }) {
      Scroll() {
        ChatDetailBottomMediaSheet({
          selectedMediaCount: $selectedMediaCount,
          animate: $animate,
          text: $text,
          shouldSendMessage: $shouldSendMessage,
          currentDetents: this.currentDetents,
          title: $mediaSheetTitle,
          selectedMedias: $selectedMedias,
        })
      }
      .nestedScroll({
        scrollForward: NestedScrollMode.PARENT_FIRST,
        scrollBackward: NestedScrollMode.SELF_ONLY,
      })
    }
    .height("100%")
      .width("100%")
  }

  @Builder
  InputRow() {
    Flex({ alignItems: ItemAlign.Center }) {
      Column() {
        StandardIcon({ icon: $r('sys.symbol.more') })
      }
      .flexBasis(HomeConstants.FLEX_BASIS_AUTO)
        .padding({
          right: $r('app.float.chat_detail_bottom_padding'),
          left: $r('app.float.chat_detail_bottom_padding'),
        })
        .bindSheet($$this.isShowMediaSheet, this.MediaSheet(), {
          height: "75%",
          dragBar: false,
          detents: [SheetSize.MEDIUM, "100%"],
          scrollSizeMode: ScrollSizeMode.CONTINUOUS,
          onAppear: () => {
          },
          onHeightDidChange: (height: number) => {
            Logger.debug("MediaSheet onHeightDidChange: " + height);
            this.continuousChatDetailBlurRadius = height / (700 * 3.25) * MAX_BLUR_RADIUS;
          },
          onWillDisappear: () => {
            Logger.debug("MediaSheet onWillDisappear");
            this.discreteChatDetailBlurRadius = 0;
            this.isShowMediaSheet = false;
          },
          onDisappear: () => {
            Logger.debug("MediaSheet onDisappear before unset isShowMediaSheet state: " + this.isShowMediaSheet);
            this.isShowMediaSheet = false;
            this.clearSendTracking();
            this.selectedMedias = [];
            this.selectedMediaCount = 0;
            Logger.debug("MediaSheet onDisappear after unset isShowMediaSheet state: " + this.isShowMediaSheet);
          },
          onDetentsDidChange: (detents: number) => {
            Logger.debug("MediaSheet onDetentsDidChange: " + detents);
            this.currentDetents = detents;
          },
          title: {
            title: this.mediaSheetTitle
          }
        })
        .onClick(() => {
          Logger.debug("MediaSheet onClick");
          this.isShowMediaSheet = !this.isShowMediaSheet;
          Logger.debug("MediaSheet onclick current isShowMediaSheet state: " + this.isShowMediaSheet);
        })

      Blank()
      Column() {
        TextArea({
          text: this.text,
        })
          .opacity(0.5)
          .borderRadius(HomeConstants.CHAT_DETAIL_BOTTOM_TEXT_RADIUS)
          .flexGrow(BaseConstants.FLEX_GROW_ONE)
          .padding({ right: $r('app.float.chat_detail_bottom_text_padding') })
          .enterKeyType(EnterKeyType.Send)
          .onChange((text: string) => {
            this.text = text;
          })
          .onSubmit((enterKey: EnterKeyType) => {
            if (enterKey == EnterKeyType.Send) {
              try {
                this.sendMessage();
                Logger.debug("sendMessage: " + this.text);
              } catch (e) {
                Logger.error("sendMessage error: " + e.message);
              }
            }
          })
      }
      .flexBasis(HomeConstants.FLEX_BASIS_AUTO)

      if (this.text.length > 0) {
        this.SendMsgBtn()
      } else {
        Column() {
          SymbolGlyph($r('sys.symbol.face_smiling'))
            .fontSize(25)
            .renderingStrategy(SymbolRenderingStrategy.SINGLE)
            .fontColor([$r('sys.color.ohos_id_color_text_primary')])
            .backgroundColor(Color.Transparent)
        }
      .flexBasis(HomeConstants.FLEX_BASIS_AUTO)
          .padding({
            left: $r('app.float.chat_detail_bottom_padding'),
            right: $r('app.float.chat_detail_bottom_padding'),
          })


        Column() {
          SymbolGlyph($r('sys.symbol.plus_square'))
            .fontSize(25)
            .renderingStrategy(SymbolRenderingStrategy.SINGLE)
            .fontColor([$r('sys.color.ohos_id_color_text_primary')])
            .backgroundColor(Color.Transparent)
        }
      .padding({
          right: $r('app.float.chat_detail_bottom_padding'),
          left: $r('app.float.chat_detail_bottom_padding'),
        })
      }
    }
  }

  build() {
    Column() {
      if (this.replyToMessageId !== undefined) {
        Row() {
          ForEach([this.replyToMessageId], (id: number) => {
            ReplyToPreview({ replyToMessageId: id })
              .layoutWeight(1)
          }, (id: number) => id.toString())

          Button() {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(20)
              .renderingStrategy(SymbolRenderingStrategy.SINGLE)
              .fontColor([$r('sys.color.ohos_id_color_text_primary')])
          }
          .width(32)
          .height(32)
          .backgroundColor(Color.Transparent)
          .margin({ left: 4 })
          .onClick(() => {
            this.replyToMessageId = undefined;
          })
        }
        .width("100%")
        .padding({
          left: $r('app.float.chat_detail_bottom_padding'),
          right: $r('app.float.chat_detail_bottom_padding'),
          bottom: $r('app.float.chat_detail_bottom_padding'),
        })
        .alignItems(VerticalAlign.Center)
      }
      this.InputRow()
    }
    .padding({
      top: $r('app.float.chat_detail_bottom_padding'),
      bottom: $r('app.float.chat_detail_bottom_padding'),
    })
    .width(BaseConstants.FULL_WIDTH)
    .backgroundBlurStyle(BlurStyle.Thin)
    .backgroundColor(Color.Transparent)
    .expandSafeArea([SafeAreaType.SYSTEM])
  }

  sendMessage() {
    if (!this.currentChatId) {
      return;
    }
    if (this.isSending) {
      Logger.warn("sendMessage ignored: previous send still in flight");
      return;
    }
    const chatId: string = this.currentChatId;
    const nativeChatId: number = parseInt(chatId);
    const textSnapshot: string = this.text;
    const replyToId: number | undefined = this.replyToMessageId;
    const mediaSnapshot: Array<string> = [...this.selectedMedias];
    const epoch: number = ++this.sendEpoch;
    let delivered: boolean = false;
    this.isSending = true;
    this.inFlightUris = new Set<string>(mediaSnapshot);
    this.deselectedDuringSend = new Set<string>();

    try {
      sendMessage(
        nativeChatId,
        textSnapshot,
        replyToId,
        mediaSnapshot,
        (index: number, progress: number) => {
          this.updateProgress(index, progress);
        }
      )
        .then((messages: NativeMessage[]) => {
          delivered = true;
          // Epoch bumps on chat switch and each send; a stale settle must not touch current state.
          if (epoch === this.sendEpoch) {
            this.isSending = false;
            if (this.replyToMessageId === replyToId) {
              this.replyToMessageId = undefined;
            }
            const deselected = new Set<string>(this.deselectedDuringSend);
            this.clearSendTracking();
            // isSending is false and tracking cleared BEFORE this assignment, so its watcher is inert.
            // S2 semantics: !inSnapshot || deselected
            this.selectedMedias = this.selectedMedias.filter((u: string) =>
              !mediaSnapshot.includes(u) || deselected.has(u));
            this.selectedMediaCount = this.selectedMedias.length;
          }

          if (!messages || messages.length === 0) {
            Logger.error("sendMessage resolved with no messages");
            return;
          }

          const list = this.messagesOfChatMap.get(chatId);
          let newestIndex = -1;
          for (let i = 0; i < messages.length; i++) {
            const m = messages[i];
            if (!m) {
              continue;
            }
            try {
              list?.push(Message.fromNative(m));
              newestIndex = i;
            } catch (e) {
              Logger.error("sendMessage: Message.fromNative failed: " + (e as Error).message);
            }
          }

          const chat = this.chatDataSource.get(chatId);
          if (chat && newestIndex >= 0) {
            const newest = messages[newestIndex];
            chat.lastMessageId = newest.messageId;
            chat.lastMessageSenderName = newest.senderName;
            chat.lastMessageText = newest.text;
            chat.lastMessageTimestamp = newest.timestamp;
            this.chatDataSource.add(chat);
          }
        })
        .catch((err: Error) => {
          Logger.error("sendMessage error: " + err.message);
          if (epoch === this.sendEpoch) {
            this.isSending = false;
            this.clearSendTracking();
            if (delivered) {
              return;
            }
            if (this.text === "" && textSnapshot !== "") {
              this.text = textSnapshot;
            }
          }
        });
    } catch (error) {
      this.isSending = false;
      this.clearSendTracking();
      Logger.error("sendMessage synchronous error: " + (error as Error).message);
      return;
    }
    this.text = "";
  }

  async updateProgress(media_index: number, progress: number) {
    // TODO: implement update media sending progress
    Logger.debug("updateProgress: " + media_index + " " + progress);
  }
}
