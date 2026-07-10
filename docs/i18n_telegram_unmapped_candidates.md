# Telegram Localization Mapping Review

Generated for the Telegram language-pack migration. Mapped strings use Telegram language-pack keys at runtime; unmapped strings keep Mithka localizations until reviewed.

- Total app strings: 989
- Mapped to Telegram keys: 598
- Unmapped app strings: 391

## Custom Chinese Telegram Pack Overrides

The `zhhanscn-qq` Telegram language pack keeps standard Telegram concepts on
the upstream keys, while overriding familiar Chinese glossary terms only where
the app maps to the same Telegram concept. These overrides were applied to the
Android pack on `translations.telegram.org` because Mithka resolves TDLib-style
language-pack keys:

| Telegram key | Custom Chinese value | Reason |
| --- | --- | --- |
| `PinMessage` | 群待办 | Message pin action uses the familiar group-todo term. |
| `UnpinMessage` | 取消群待办 | Message unpin action matches `PinMessage`. |
| `MessagePinnedHint` | 已设为群待办。 | Toast after setting a message pin. |
| `MessageUnpinnedHint` | 已取消群待办。 | Toast after removing a message pin. |
| `PinnedMessages` | 群待办 | Pinned message list label. |
| `PinnedMessage` | 群待办 | Singular pinned-message label. |
| `UserRestrictionsPinMessages` | 设置群待办 | Group permission label for pinning messages. |
| `SearchAllChatsShort` | 消息 | Chat-list tab/search concept in the familiar glossary. |
| `NewGroup` | 创建群聊 | Familiar group-chat wording. |
| `JoinGroup` | 加入群聊 | Familiar group-chat wording. |
| `LeaveMegaMenu` | 退出群聊 | Familiar group-chat wording. |
| `GroupName` | 群名称 | Familiar group wording. |
| `ManageGroup` | 管理群 | Familiar group wording. |
| `SettingsFolders` | 聊天分组 | Familiar folder/grouping wording. |
| `FilterNew` | 新建分组 | Familiar folder/grouping wording. |
| `FilterNameHeader` | 分组名称 | Familiar folder/grouping wording. |
| `AddContactChat` | 加好友 | Familiar contact-add wording. |
| `AttachSticker` | 表情包 | Familiar sticker wording. |
| `BlockedUsers` | 黑名单 | Familiar blocked-user list wording. |
| `NoBlocked` | 黑名单为空 | Familiar blocked-user empty state. |

## Unmapped Strings

| Mithka key | English text | Similar Telegram concept candidates |
| --- | --- | --- |
| `aboutTitle` | About | - |
| `aboutVersion` | Version {value1} | - |
| `aboutWebsite` | Website | - |
| `accountBackupCopied` | Pyrogram session copied | CurrentSession / OtherSessions |
| `accountBackupCopyPyrogramMessage` | This copies the active Telegram authorization session to the clipboard. Anyone with this string can sign in as this account. | Message / SendMessage / SearchMessages; CurrentSession / OtherSessions |
| `accountBackupCopyPyrogramSession` | Copy Pyrogram session | CurrentSession / OtherSessions |
| `accountBackupCopyPyrogramTitle` | Copy Pyrogram session? | CurrentSession / OtherSessions |
| `accountBackupCreate` | Back up current account to Keychain | - |
| `accountBackupDeleteMessage` | This removes the saved session from Keychain. The Telegram session is not revoked. | Message / SendMessage / SearchMessages; Delete / DeleteChat / DeleteAll / DeleteAllFrom; Save / SavedMessages; CurrentSession / OtherSessions |
| `accountBackupDeleteInvalidSession` | Delete Saved Session | Delete / DeleteChat / DeleteAll / DeleteAllFrom; Save / SavedMessages; CurrentSession / OtherSessions |
| `accountBackupDeleteTitle` | Delete saved session? | Delete / DeleteChat / DeleteAll / DeleteAllFrom; Save / SavedMessages; CurrentSession / OtherSessions |
| `accountBackupEmpty` | No account sessions are backed up yet. | CurrentSession / OtherSessions |
| `accountBackupEnabled` | Back up accounts | - |
| `accountBackupFreshSessionCreate` | Create New Session | CurrentSession / OtherSessions |
| `accountBackupFreshSessionInteractive` | Continue the login step to finish creating the new session. | CurrentSession / OtherSessions; BotAuthLogin / AuthAnotherClient |
| `accountBackupFreshSessionMessage` | The restored session is ready. To avoid using the same Telegram session on multiple devices, Mithka can create a new session from it with QR login. Telegram may ask for your two-step verification password. | Message / SendMessage / SearchMessages; Devices / CurrentSession / OtherSessions; CurrentSession / OtherSessions; TwoStepVerification / Password; BotAuthLogin / AuthAnotherClient; AuthAnotherClient / QrCode |
| `accountBackupFreshSessionReady` | Created a new session in slot {value1} | CurrentSession / OtherSessions |
| `accountBackupFreshSessionTitle` | Create a new session? | CurrentSession / OtherSessions |
| `accountBackupFreshSessionUseRestored` | Use Restored Session | CurrentSession / OtherSessions |
| `accountBackupFreshSessionWaiting` | Creating the new session... | CurrentSession / OtherSessions |
| `accountBackupInvalidImportedMessage` | This session string is no longer valid or may have been revoked. Please export a fresh session from a logged-in device. | Message / SendMessage / SearchMessages; Devices / CurrentSession / OtherSessions; CurrentSession / OtherSessions |
| `accountBackupInvalidMessage` | The saved session for {value1} is no longer valid or may have been revoked. Delete this saved session from Keychain? | Message / SendMessage / SearchMessages; Delete / DeleteChat / DeleteAll / DeleteAllFrom; Save / SavedMessages; CurrentSession / OtherSessions |
| `accountBackupInvalidTitle` | Session no longer valid | CurrentSession / OtherSessions |
| `accountBackupImported` | Imported to account slot {value1} | - |
| `accountBackupIOSOnly` | Account backup is available on iOS only. | - |
| `accountBackupLoadPyrogramConfirm` | Load Session | CurrentSession / OtherSessions |
| `accountBackupLoadPyrogramMessage` | Paste a Pyrogram-compatible Telegram session string. The session will be imported locally as an account if it is still valid. | Message / SendMessage / SearchMessages; CurrentSession / OtherSessions |
| `accountBackupLoadPyrogramPlaceholder` | Pyrogram session string | CurrentSession / OtherSessions |
| `accountBackupLoadPyrogramSession` | Load Pyrogram session | CurrentSession / OtherSessions |
| `accountBackupLoadPyrogramTitle` | Load Pyrogram session | CurrentSession / OtherSessions |
| `accountBackupNotice` | Only the TDLib session file is stored in the device Keychain. Message databases, media, logs, and caches are not backed up. To transfer this Keychain item to a new device, restore from an encrypted device backup. | Message / SendMessage / SearchMessages; AttachDocument / SharedFilesTab; Devices / CurrentSession / OtherSessions; CurrentSession / OtherSessions |
| `accountBackupRestoreAccount` | Restore saved account | Save / SavedMessages |
| `accountBackupRestored` | Restored to account slot {value1} | - |
| `accountBackupRestoreMessage` | This imports the saved session as a new account. The session must still be active on Telegram servers. | Message / SendMessage / SearchMessages; Save / SavedMessages; CurrentSession / OtherSessions |
| `accountBackupRestoreTitle` | Restore saved session? | Save / SavedMessages; CurrentSession / OtherSessions |
| `accountBackupSaved` | Session saved ({value1}) | Save / SavedMessages; CurrentSession / OtherSessions |
| `accountBackupSessions` | Saved Sessions | Save / SavedMessages; CurrentSession / OtherSessions |
| `accountBackupTitle` | Account Backup | - |
| `accountBackupUserId` | User ID: {value1} | - |
| `addMembersDoneWithCount` | Done ({value1}) | Members / GroupMembers / ChannelMembers |
| `addMembersInvitePermissionError` | Invite failed. You may not have permission. | Members / GroupMembers / ChannelMembers; InviteLink / AddMember |
| `addPeopleFindGroups` | Find Groups | NewGroup / GroupMembers / Groups |
| `addPeopleFindPeople` | Find People | - |
| `addPeopleGroupNameOrLinkPlaceholder` | Group name/link | NewGroup / GroupMembers / Groups; SharedLinksTab / ShareLink |
| `addPeopleNoGroupsOrChannelsFound` | No groups or channels found | NewGroup / GroupMembers / Groups; Channel / ChannelSettings / ChannelMembers |
| `addPeopleUsernameOrPhonePlaceholder` | Username/phone number | Phone / PhoneNumber; Username / SetUsernameHeader |
| `apiCredentialsCustomClientApi` | Custom Client API | - |
| `apiCredentialsDescription` | Off by default. When enabled, fill in your own Telegram client API credentials; they take effect on the next launch or after signing in again. Acceleration stays off until every field is filled in. | - |
| `apiCredentialsTitle` | Video and Download Acceleration | AttachVideo / Videos; Download / Downloaded |
| `appIconBlueGradient` | Blue Gradient | - |
| `appIconChangeFailed` | Failed to change app icon | - |
| `appIconPixel` | 8-bit Pixel | - |
| `appIconPurpleGradient` | Purple Gradient | - |
| `appIconUnsupported` | This platform or launcher may not support changing the app icon. | - |
| `appIconWhite` | Pure White | - |
| `appearanceAddFont` | Add Font | FontSize / FontType |
| `appearanceAddTextFont` | Add Text Font | FontSize / FontType |
| `appearanceCacheCleaned` | Cleaned | ClearCache / StorageUsage |
| `appearanceCacheFiles` | Cache Files | AttachDocument / SharedFilesTab; ClearCache / StorageUsage |
| `appearanceCacheRefreshed` | Refreshed | ClearCache / StorageUsage |
| `appearanceCapUnreadCountAt99` | Show 99+ after 99 | - |
| `appearanceChatList` | Chat List | SearchAllChatsShort / SelectChat |
| `appearanceChatView` | Chat View | SearchAllChatsShort / SelectChat |
| `appearanceCleanableSize` | Cleanable | - |
| `appearanceCleanUnusedFonts` | Clean Unused Fonts | FontSize / FontType |
| `appearanceClearTextFonts` | Clear Text Fonts | FontSize / FontType |
| `appearanceColor` | Color | Exact upstream text: NotificationsLedColor |
| `appearanceDisplay` | Display | - |
| `appearanceEmojiFont` | Emoji Font | Emoji1..Emoji7 / SetEmojiStatus; FontSize / FontType |
| `appearanceEmojiFontCatalogDescription` | The font list comes from the iebb/emojifonts manifest. Selected fonts are downloaded from GitHub Releases. Previews come from Emojipedia. | Emoji1..Emoji7 / SetEmojiStatus; Download / Downloaded; FontSize / FontType |
| `appearanceFileCount` | {value1} | AttachDocument / SharedFilesTab |
| `appearanceFont` | Font | FontSize / FontType |
| `appearanceFontCache` | Font Cache | ClearCache / StorageUsage; FontSize / FontType |
| `appearanceFontCacheDescription` | Manages only runtime-downloaded Google font caches. Files used by the current font chain, monospace font, and emoji font are kept. | AttachDocument / SharedFilesTab; Emoji1..Emoji7 / SetEmojiStatus; Download / Downloaded; ClearCache / StorageUsage; FontSize / FontType |
| `appearanceFontChainDescription` | Text fonts are applied in order across the interface. The emoji font is preferred for emoji. The monospace font is used for code blocks. | Emoji1..Emoji7 / SetEmojiStatus; FontSize / FontType |
| `appearanceFontDownloadFailedName` | {value1} · Download failed | Download / Downloaded; FontSize / FontType |
| `appearanceFontInUse` | In Use | FontSize / FontType |
| `appearanceFontUnused` | Unused | FontSize / FontType |
| `appearanceGoogleDownloaded` | Google downloaded | Download / Downloaded |
| `appearanceGroupAssistantPosition` | Group Assistant Position | NewGroup / GroupMembers / Groups |
| `appearanceHidePhoneInSidebar` | Hide Phone Number in Sidebar | Phone / PhoneNumber |
| `appearanceInterfaceSize` | Interface Size | - |
| `appearanceInUseSize` | In Use | - |
| `appearanceManage` | Manage | - |
| `appearanceMergeConsecutiveImages` | Merge Consecutive Images | AttachPhoto / SharedMediaTab |
| `appearanceMode` | Mode | - |
| `appearanceMonospaceFont` | Monospace Font | FontSize / FontType |
| `appearanceNoCleanableFonts` | Nothing to clean | FontSize / FontType |
| `appearanceNoDownloadedFontCache` | No downloaded font cache. | Download / Downloaded; ClearCache / StorageUsage; FontSize / FontType |
| `appearanceRefreshCacheList` | Refresh Cache List | ClearCache / StorageUsage |
| `appearanceRoundGroupAvatars` | Show Group Avatars as Circles | NewGroup / GroupMembers / Groups |
| `appearanceShowChatFiltersOnTop` | Show Chat Filters at Top | SearchAllChatsShort / SelectChat |
| `appearanceShowChatListSearch` | Show Chat List Search | SearchAllChatsShort / SelectChat; Search / SearchMessages / NoResult |
| `appearanceShowEditAndReadMarks` | Show Edit and Read Marks | - |
| `appearanceShowGroupMemberTitles` | Show Group Member Titles | NewGroup / GroupMembers / Groups; Members / GroupMembers / ChannelMembers |
| `appearanceShowPremiumNameColor` | Show Premium Name Color | TelegramPremiumShort |
| `appearanceShowPremiumStatusEmoji` | Show Premium Status Emoji | Emoji1..Emoji7 / SetEmojiStatus; TelegramPremiumShort |
| `appearanceShowUnreadChatCount` | Show Unread Chat Count | SearchAllChatsShort / SelectChat |
| `appearanceSize` | Size | - |
| `appearanceSystemEmojiFont` | System emoji font | Emoji1..Emoji7 / SetEmojiStatus; FontSize / FontType |
| `appearanceTextFont` | Text Font | FontSize / FontType |
| `appearanceTextFontOrderHint` | Text fonts are applied in order. Characters not covered continue using the system font. | FontSize / FontType |
| `appearanceTextFontUnsetHint` | No text font set. Using the system default. | FontSize / FontType |
| `appearanceTotalSize` | Total Size | - |
| `appearanceUnreadBadge` | Unread Badge | - |
| `appLocaleArabic` | العربية | - |
| `appLocaleEnglish` | English | Exact upstream text: LanguageName, English, LanguageNameInEnglish |
| `appLocaleFollowSystem` | Follow System | - |
| `appLocaleFrench` | Français | - |
| `appLocaleGerman` | Deutsch | - |
| `appLocaleHindi` | हिन्दी | - |
| `appLocaleIndonesian` | Indonesia | - |
| `appLocaleItalian` | Italiano | - |
| `appLocaleJapanese` | 日本語 | - |
| `appLocaleKorean` | 한국어 | - |
| `appLocaleMalay` | Melayu | - |
| `appLocalePortuguese` | Português | - |
| `appLocaleRussian` | Русский | - |
| `appLocaleSimplifiedChinese` | 简体中文 | - |
| `appLocaleSpanish` | Español | - |
| `appLocaleThai` | ไทย | - |
| `appLocaleTraditionalChinese` | 繁體中文 | - |
| `appLocaleTurkish` | Türkçe | - |
| `appLocaleUkrainian` | Українська | - |
| `appLocaleVietnamese` | Tiếng Việt | - |
| `archivedChatsGroupAssistant` | Group Assistant | NewGroup / GroupMembers / Groups |
| `authCodeSent` | Verification code sent | - |
| `authCodeSentByFlashCall` | You will receive a flash call | Call / VideoCall / VoipConnecting |
| `authCodeSentByPhoneCall` | You’ll receive a phone call with the verification code | Call / VideoCall / VoipConnecting; Phone / PhoneNumber |
| `authCodeSentBySms` | The verification code was sent by SMS | - |
| `callIncomingCallInvite` | invited you to a {value1} call | Call / VideoCall / VoipConnecting; InviteLink / AddMember |
| `callWaitingForInviteAccept` | Waiting for the other person to accept… | Call / VideoCall / VoipConnecting; InviteLink / AddMember |
| `chatAdminsOnlyPosting` | Only admins can post | SearchAllChatsShort / SelectChat |
| `chatAllMembersMuted` | All members are muted | SearchAllChatsShort / SelectChat; Members / GroupMembers / ChannelMembers |
| `chatAndOthersCount` |  and {value1} others | SearchAllChatsShort / SelectChat |
| `chatContactCallsOnly` | Calls are only supported with contacts | SearchAllChatsShort / SelectChat; Contacts / AddContactChat / SelectContact; Call / VideoCall / VoipConnecting |
| `chatBlockUserMessage` | Block this sender, report the message for review, and remove their messages from this chat immediately? | Message / SendMessage / SearchMessages; SearchAllChatsShort / SelectChat; Delete / Remove; BlockUser / BlockedUsers; ReportChat / ReportChatSent |
| `chatForwardedToName` | Forwarded to {value1} | SearchAllChatsShort / SelectChat; Forward / ForwardTo |
| `chatForwardProtected` | This message is protected and can’t be forwarded | Message / SendMessage / SearchMessages; SearchAllChatsShort / SelectChat; Forward / ForwardTo |
| `chatForwardRemoveSender` | Remove sender | SearchAllChatsShort / SelectChat; Delete / Remove; Forward / ForwardTo |
| `chatInfoClearHistoryDescription` | This deletes the local chat history but does not leave the chat. | SearchAllChatsShort / SelectChat |
| `chatInfoClearHistoryIrreversibleWarning` | After clearing, history on this device can’t be recovered. | SearchAllChatsShort / SelectChat; Devices / CurrentSession / OtherSessions |
| `chatInfoConfirmAgain` | Confirm again | SearchAllChatsShort / SelectChat |
| `chatInfoDisableExplicitFolderWarning` | Turning off explicit folders will remove this chat. If it still matches automatic folder rules, it will be added to the exclusions list. | SearchAllChatsShort / SelectChat; SettingsFolders / FilterNew / FilterNameHeader; Delete / Remove |
| `chatInfoFolderName` | Folder {value1} | SearchAllChatsShort / SelectChat; SettingsFolders / FilterNew / FilterNameHeader |
| `chatInfoGroupAlbum` | Group album | SearchAllChatsShort / SelectChat; NewGroup / GroupMembers / Groups |
| `chatInfoGroupApps` | Group apps | SearchAllChatsShort / SelectChat; NewGroup / GroupMembers / Groups |
| `chatInfoGroupChat` | Group chat | SearchAllChatsShort / SelectChat; NewGroup / GroupMembers / Groups |
| `chatInfoGroupId` | Group ID: {value1} | SearchAllChatsShort / SelectChat; NewGroup / GroupMembers / Groups |
| `chatInfoMoveToGroupAssistant` | Move to Group Assistant | SearchAllChatsShort / SelectChat; NewGroup / GroupMembers / Groups |
| `chatInfoTitle` | Chat Info | SearchAllChatsShort / SelectChat |
| `chatListAddFriendOrGroup` | Add friend/group | SearchAllChatsShort / SelectChat; NewGroup / GroupMembers / Groups |
| `chatListBlockedPlaceholder` | [Blocked] | SearchAllChatsShort / SelectChat; BlockUser / BlockedUsers |
| `chatMeLabel` | Me | SearchAllChatsShort / SelectChat |
| `chatMembersRemoveMemberConfirmation` | Remove {value1} from the group? | SearchAllChatsShort / SelectChat; NewGroup / GroupMembers / Groups; Members / GroupMembers / ChannelMembers; Delete / Remove |
| `chatMembersRemoveMemberTitle` | Remove Member | SearchAllChatsShort / SelectChat; Members / GroupMembers / ChannelMembers; Delete / Remove |
| `chatMessageRequired` | Message can’t be empty | Message / SendMessage / SearchMessages; SearchAllChatsShort / SelectChat |
| `chatMessagesSavedCount` | Saved {value1} messages | Message / SendMessage / SearchMessages; SearchAllChatsShort / SelectChat; Save / SavedMessages |
| `chatReportMessage` | Report this message as objectionable or abusive content? | Message / SendMessage / SearchMessages; SearchAllChatsShort / SelectChat; ReportChat / ReportChatSent |
| `chatPeopleDoingAction` | {value1} people active… | SearchAllChatsShort / SelectChat |
| `chatPeopleTyping` | {value1} people are typing… | SearchAllChatsShort / SelectChat |
| `chatRestrictedTelegramTosMessage` | This group can’t be displayed because it violated Telegram's Terms of Service. You can go back or leave the group. | Message / SendMessage / SearchMessages; SearchAllChatsShort / SelectChat; NewGroup / GroupMembers / Groups |
| `chatRestrictedTitle` | Safety notice | SearchAllChatsShort / SelectChat |
| `chatSavedToSavedMessages` | Saved to Saved Messages | Message / SendMessage / SearchMessages; SearchAllChatsShort / SelectChat; Save / SavedMessages |
| `chatsSearchPublicGroupsAndChannels` | Public groups/channels | NewGroup / GroupMembers / Groups; Channel / ChannelSettings / ChannelMembers; Search / SearchMessages / NoResult |
| `chatStickerAddSuccess` | Added to emoji | SearchAllChatsShort / SelectChat; Emoji1..Emoji7 / SetEmojiStatus; AttachSticker / ViewPackPreview |
| `chatActionWatchingAnimations` | watching animations… | SearchAllChatsShort / SelectChat |
| `chatUserFallbackName` | User {value1} | SearchAllChatsShort / SelectChat |
| `chatUserLeftGroup` | {value1} left the group | SearchAllChatsShort / SelectChat; NewGroup / GroupMembers / Groups |
| `chatUsersJoinedGroup` | {value1}{value2} joined the group | SearchAllChatsShort / SelectChat; NewGroup / GroupMembers / Groups |
| `chatUserDoingAction` | {value1} is {value2} | SearchAllChatsShort / SelectChat |
| `chatYouAreMuted` | You are muted | SearchAllChatsShort / SelectChat |
| `chatYouWereRemovedFromGroup` | You were removed from this group | SearchAllChatsShort / SelectChat; NewGroup / GroupMembers / Groups; Delete / Remove |
| `checklistComposerPremiumLimitHint` | Up to 30 items · Creating checklists requires Telegram Premium | Todo / TodoTitle / AttachChecklist; TelegramPremiumShort |
| `checklistComposerTaskLabel` | Task {value1} | Todo / TodoTitle / AttachChecklist |
| `checklistComposerTitleLabel` | Checklist title | Todo / TodoTitle / AttachChecklist |
| `commonUiMentionedBySomeoneBadge` | [Someone mentioned me] | - |
| `commonUiMentionMeBadge` | [@me] | - |
| `commonUiNewFileBadge` | [New file] | AttachDocument / SharedFilesTab |
| `composerClipboardNoImage` | No image on clipboard | AttachPhoto / SharedMediaTab |
| `composerFilePreview` | [File]{value1} | AttachDocument / SharedFilesTab |
| `composerHoldToTalk` | Hold to talk | - |
| `composerMarkdownSupportHint` | Markdown supported: **bold**, *italic*, `code`, quotes, and more | - |
| `composerMicrophonePermissionRequired` | Microphone permission required | - |
| `composerMicrophonePermissionSettings` | Allow microphone access in system settings | - |
| `composerNoEmoji` | No emoji yet | Emoji1..Emoji7 / SetEmojiStatus |
| `composerPaidMessageCost` | Sending this message costs {value1} Stars. | Message / SendMessage / SearchMessages; MessageLockedStars / Stars |
| `composerRichText` | Rich text | - |
| `composerRichTextMessageTitle` | Rich text message | Message / SendMessage / SearchMessages |
| `contactsFriends` | Friends | Contacts / AddContactChat / SelectContact |
| `contactsNoGroupChats` | No group chats yet | NewGroup / GroupMembers / Groups; Contacts / AddContactChat / SelectContact |
| `createGroupStartGroupChat` | Start group chat | SearchAllChatsShort / SelectChat; NewGroup / GroupMembers / Groups |
| `editProfileAnimatedAvatarDescription` | Use a short video as your avatar | AttachVideo / Videos |
| `editProfileBirthDay` | {value1} | - |
| `editProfileBirthMonth` | {value1} | - |
| `editProfileBirthYear` | {value1} | - |
| `editProfileChooseAvatarType` | Choose avatar type | - |
| `editProfileNameColor` | Name color | - |
| `editProfileNameColorDescription` | Used for your name and message sidebar. | Message / SendMessage / SearchMessages |
| `editProfileNoBirthYear` | No year | - |
| `editProfileProfileColor` | Profile color | - |
| `editProfileProfileColorDescription` | Used for your profile page background. | - |
| `editProfileStaticAvatarDescription` | Crop and upload a still image | AttachPhoto / SharedMediaTab |
| `editProfileTitle` | Edit profile | - |
| `editProfileUsernameUnsetHandle` | @not set | Username / SetUsernameHeader |
| `emojiPreviewFaceWithTearsOfJoy` | Face with tears of joy | Emoji1..Emoji7 / SetEmojiStatus |
| `emojiStatusNoAvailableStatuses` | No available statuses in this emoji pack | Emoji1..Emoji7 / SetEmojiStatus |
| `developerModePiPBoundsOverlay` | PiP bounds overlay | - |
| `developerModePiPBoundsOverlayDescription` | Shows the app-level PiP frame and viewport size to diagnose rotation, clipping, or overlay coverage. | - |
| `developerModeTitle` | Developer Mode | - |
| `developerModeUnlocked` | Developer Mode unlocked | - |
| `featureBottomTabs` | Bottom tabs | - |
| `fileDetailDownloadProgress` | Downloading file… ({value1}/{value2}) | AttachDocument / SharedFilesTab; Download / Downloaded |
| `generalCacheSize` | Cache size | ClearCache / StorageUsage |
| `generalOpenChatAtLatestMessage` | Open chats at latest message | Message / SendMessage / SearchMessages; SearchAllChatsShort / SelectChat |
| `generalSendMessageWithEnter` | Send messages with Enter | Message / SendMessage / SearchMessages |
| `groupManagementAdminApprovalRequired` | Admin approval required | NewGroup / GroupMembers / Groups |
| `groupManagementBasicSection` | Basic management | NewGroup / GroupMembers / Groups |
| `groupManagementEditable` | Editable | NewGroup / GroupMembers / Groups |
| `groupManagementJoinBeforePosting` | Join before posting | NewGroup / GroupMembers / Groups |
| `groupManagementJoinSection` | Join settings | NewGroup / GroupMembers / Groups |
| `groupManagementLogApprovedJoinRequest` | Approved join request | NewGroup / GroupMembers / Groups |
| `groupManagementLogChangedAdmin` | Changed admin | NewGroup / GroupMembers / Groups |
| `groupManagementLogChangedGroupDescription` | Changed group description | NewGroup / GroupMembers / Groups |
| `groupManagementLogChangedGroupName` | Changed group name | NewGroup / GroupMembers / Groups |
| `groupManagementLogChangedGroupPhoto` | Changed group photo | NewGroup / GroupMembers / Groups; AttachPhoto / SharedMediaTab |
| `groupManagementLogChangedLinkedChat` | Changed linked chat | SearchAllChatsShort / SelectChat; NewGroup / GroupMembers / Groups |
| `groupManagementLogChangedMemberPermissions` | Changed member permissions | NewGroup / GroupMembers / Groups; Members / GroupMembers / ChannelMembers |
| `groupManagementLogChangedPostingPermissions` | Changed posting permissions | NewGroup / GroupMembers / Groups |
| `groupManagementLogChangedPublicUsername` | Changed public username | NewGroup / GroupMembers / Groups; Username / SetUsernameHeader |
| `groupManagementLogChangedSlowMode` | Changed slow mode | NewGroup / GroupMembers / Groups |
| `groupManagementLogCreatedTopic` | Created topic | NewGroup / GroupMembers / Groups; Topics / NoTopics / CreateTopicsPermission |
| `groupManagementLogDeletedInviteLink` | Deleted invite link | NewGroup / GroupMembers / Groups; SharedLinksTab / ShareLink; InviteLink / AddMember; Delete / DeleteChat / DeleteAll / DeleteAllFrom |
| `groupManagementLogDeletedMessage` | Deleted message | Message / SendMessage / SearchMessages; NewGroup / GroupMembers / Groups; Delete / DeleteChat / DeleteAll / DeleteAllFrom |
| `groupManagementLogDeletedTopic` | Deleted topic | NewGroup / GroupMembers / Groups; Topics / NoTopics / CreateTopicsPermission; Delete / DeleteChat / DeleteAll / DeleteAllFrom |
| `groupManagementLogEditedInviteLink` | Edited invite link | NewGroup / GroupMembers / Groups; SharedLinksTab / ShareLink; InviteLink / AddMember |
| `groupManagementLogEditedMessage` | Edited message | Message / SendMessage / SearchMessages; NewGroup / GroupMembers / Groups |
| `groupManagementLogEditedTopic` | Edited topic | NewGroup / GroupMembers / Groups; Topics / NoTopics / CreateTopicsPermission |
| `groupManagementLogEmpty` | No management log yet | NewGroup / GroupMembers / Groups |
| `groupManagementLogGenericAdminAction` | Performed an admin action | NewGroup / GroupMembers / Groups |
| `groupManagementLogInvitedMember` | Invited member | NewGroup / GroupMembers / Groups; Members / GroupMembers / ChannelMembers; InviteLink / AddMember |
| `groupManagementLogJoinedByInviteLink` | Joined via invite link | NewGroup / GroupMembers / Groups; SharedLinksTab / ShareLink; InviteLink / AddMember |
| `groupManagementLogJoinedGroup` | Joined the group | NewGroup / GroupMembers / Groups |
| `groupManagementLogLeftGroup` | Left the group | NewGroup / GroupMembers / Groups |
| `groupManagementLogNoPermission` | You do not have permission to view the group management log | NewGroup / GroupMembers / Groups |
| `groupManagementLogRevokedInviteLink` | Revoked invite link | NewGroup / GroupMembers / Groups; SharedLinksTab / ShareLink; InviteLink / AddMember |
| `groupManagementMembersSection` | Member Management | NewGroup / GroupMembers / Groups; Members / GroupMembers / ChannelMembers |
| `groupManagementNotSet` | Not set | NewGroup / GroupMembers / Groups |
| `groupManagementPermissionEditGroupInfo` | Edit group info | NewGroup / GroupMembers / Groups |
| `groupManagementPostingPermissions` | Posting Permissions | NewGroup / GroupMembers / Groups |
| `imageEditObscure` | Obscure | AttachPhoto / SharedMediaTab |
| `imageEditTitle` | Edit Image | AttachPhoto / SharedMediaTab |
| `keywordBlockerDescription` | After you add keywords, matching messages will be hidden in chats and will not trigger local notifications. Supports plain keywords, re:regex, regex:regex, and /regex/i. Remote lists use one rule per line; lines starting with # or // are comments. | Message / SendMessage / SearchMessages; CommentsNoNumber / RepliesTitle |
| `keywordBlockerInputPlaceholder` | Enter keyword | - |
| `keywordBlockerListUrl` | Keyword list URL | - |
| `keywordBlockerAddFromMessageTitle` | Block keyword | Message / SendMessage / SearchMessages; BlockUser / BlockedUsers |
| `keywordBlockerRuleAdded` | Blocked keyword: {value1} | BlockUser / BlockedUsers |
| `keywordBlockerRulesAdded` | Added {value1} rules | - |
| `keywordBlockerRulesUpToDate` | Rules are up to date | - |
| `keywordBlockerTitle` | Keyword Blocker | - |
| `languageMithkaLanguage` | Mithka language | SettingsLanguage |
| `languageTelegramFollowMithka` | Follow Mithka language | SettingsLanguage |
| `languageTelegramLanguage` | Telegram language | SettingsLanguage |
| `languageTelegramOfficial` | Official | SettingsLanguage |
| `languageTelegramUsing` | Using {value1} | SettingsLanguage |
| `linkHandlerQrLoginWarning` | This link can approve another device signing in to your Telegram account. Make sure it is you signing in. | SharedLinksTab / ShareLink; Devices / CurrentSession / OtherSessions; BotAuthLogin / AuthAnotherClient; AuthAnotherClient / QrCode |
| `listSeparator` | ,  | - |
| `loginBackToAccount` | Back to {value1} | BotAuthLogin / AuthAnotherClient |
| `loginBackToPreviousAccount` | Back to previous account | BotAuthLogin / AuthAnotherClient |
| `loginCodeSentByFirebase` | Enter the code from the system verification prompt. | BotAuthLogin / AuthAnotherClient |
| `loginCodeSentByFlashCall` | Enter the code from the incoming call matching {value1}. | Call / VideoCall / VoipConnecting; BotAuthLogin / AuthAnotherClient |
| `loginCodeSentByFragment` | Enter the code from Fragment. | BotAuthLogin / AuthAnotherClient |
| `loginCodeSentByMissedCall` | Enter the last {value2} digits of the missed call from {value1}. | Call / VideoCall / VoipConnecting; BotAuthLogin / AuthAnotherClient |
| `loginCodeWillBeSentToNumber` | We will send a one-time login code to this number | BotAuthLogin / AuthAnotherClient |
| `loginCompleteRegistration` | Complete registration | BotAuthLogin / AuthAnotherClient |
| `loginConfigureCustomApi` | Configure custom API | BotAuthLogin / AuthAnotherClient |
| `loginNewAccountNicknamePrompt` | This is a new account. Please enter a nickname | BotAuthLogin / AuthAnotherClient |
| `loginPasswordHint` | Password hint: {value1} | TwoStepVerification / Password; BotAuthLogin / AuthAnotherClient |
| `loginReenterPhoneNumber` | Re-enter phone number | BotAuthLogin / AuthAnotherClient; Phone / PhoneNumber |
| `loginTelegramApiCredentialsMissing` | Telegram API credentials are not configured | BotAuthLogin / AuthAnotherClient |
| `loginTelegramApiPortalInstructions` | (You can get them from my.telegram.org.) | BotAuthLogin / AuthAnotherClient |
| `loginTelegramApiSecretsInstructions` | Enter your own Telegram client api_id and api_hash | BotAuthLogin / AuthAnotherClient |
| `loginTermsBody` | By using this app, you must follow Telegram's Terms of Service. Mithka signs in to existing Telegram accounts and has zero tolerance for objectionable content or abusive users. You can filter messages with Keyword Blocker, report objectionable content through Telegram, and block abusive users through Telegram. Blocking removes that sender's messages from your view immediately. | Message / SendMessage / SearchMessages; BlockUser / BlockedUsers; ReportChat / ReportChatSent; BotAuthLogin / AuthAnotherClient |
| `markdownLabel` | Markdown | - |
| `messageActionBlockKeyword` | Block keyword | Message / SendMessage / SearchMessages; BlockUser / BlockedUsers |
| `messageActionPlayMuted` | Play muted | Message / SendMessage / SearchMessages |
| `messageBubbleCallDuration` | Call duration {value1} | Message / SendMessage / SearchMessages; Call / VideoCall / VoipConnecting |
| `momentsCreatePostTitle` | Create post | - |
| `momentsLiked` | Liked | - |
| `momentsLikedByCount` | Liked by {value1} | - |
| `momentsLikedByListWithOthers` | {value1}, ... and {value2} others liked this | - |
| `momentsNewPostsCount` | {value1} new posts | - |
| `momentsNoFriendPosts` | No posts from friends yet | - |
| `momentsNoPostableChannels` | No channels available to post to | Channel / ChannelSettings / ChannelMembers |
| `momentsNoSearchableChannels` | No searchable channels | Channel / ChannelSettings / ChannelMembers |
| `momentsNotifySubscribers` | Notify subscribers | - |
| `momentsPostAction` | Post | Exact upstream text: StarsTransactionMessage |
| `momentsPostedTo` | Posted to {value1} | - |
| `momentsPublishTo` | Post to | - |
| `momentsReplied` | Replied | - |
| `momentsSearchChannelPosts` | Search channel posts | Channel / ChannelSettings / ChannelMembers; Search / SearchMessages / NoResult |
| `momentsSearchJoinedChannelPosts` | Search posts from joined channels | Channel / ChannelSettings / ChannelMembers; Search / SearchMessages / NoResult |
| `momentsShareSomethingPlaceholder` | Share something new... | - |
| `momentsUserLiked` | {value1} liked this | - |
| `musicPlayerAddedToPlaylist` | Added to playlist | AttachMusic / SharedMusicTab |
| `musicPlayerAlreadyInPlaylist` | Already in the playlist | AttachMusic / SharedMusicTab |
| `musicPlayerQueueTitleWithCount` | Play queue ({value1}) | AttachMusic / SharedMusicTab |
| `netemoMusicLabel` | Netemo music | AttachMusic / SharedMusicTab |
| `pollComposerQuestionRequired` | Enter a question | Poll / NewPoll / AddAnOption |
| `pollComposerSingleChoiceLimitHint` | Single choice · Up to 10 options | Poll / NewPoll / AddAnOption |
| `privacyDeleteTelegramAccountMessage` | Telegram accounts are managed by Telegram and can be set to delete automatically after a period of inactivity in Telegram settings. To delete sooner, open Telegram's official account deletion page and complete deletion directly with Telegram. | Message / SendMessage / SearchMessages; Delete / DeleteChat / DeleteAll / DeleteAllFrom; PrivacySettings / PrivacyTitle |
| `privacyDeleteTelegramAccountOpen` | Open deletion page | Delete / DeleteChat / DeleteAll / DeleteAllFrom; PrivacySettings / PrivacyTitle |
| `privacyDeviceApp` | App | PrivacySettings / PrivacyTitle; Devices / CurrentSession / OtherSessions |
| `privacyNoOtherDevices` | No other devices are logged in | PrivacySettings / PrivacyTitle; Devices / CurrentSession / OtherSessions |
| `privacyScanLoginQrSubtitle` | Scan the QR code shown on another Telegram login screen to approve that device. | PrivacySettings / PrivacyTitle; Devices / CurrentSession / OtherSessions; BotAuthLogin / AuthAnotherClient; AuthAnotherClient / QrCode |
| `privacyTerminateSessionMessage` | Terminate {value1}? | Message / SendMessage / SearchMessages; PrivacySettings / PrivacyTitle; CurrentSession / OtherSessions |
| `profileDetailAudioVideoCall` | Audio/video call | Call / VideoCall / VoipConnecting; AttachVideo / Videos |
| `profileDetailCardLinkCopied` | Profile card link copied | SharedLinksTab / ShareLink |
| `profileDetailFeaturedPhotos` | Featured photos | AttachPhoto / SharedMediaTab |
| `profileDetailMonthDayDate` | {value1}/{value2} | - |
| `profileDetailYearMonthDate` | {value1}/{value2} | - |
| `profileLogOutAccountConfirm` | This will revoke the Telegram session for {value1}, remove its local data, and delete its saved Keychain backup. | Delete / DeleteChat / DeleteAll / DeleteAllFrom; Delete / Remove; Save / SavedMessages; CurrentSession / OtherSessions |
| `profileRemoveAccountConfirm` | {value1} will be removed from this device. The Telegram session stays active on Telegram and can be restored from a saved backup. | Delete / Remove; Save / SavedMessages; Devices / CurrentSession / OtherSessions; CurrentSession / OtherSessions |
| `proxyDescription` | The proxy is only used to connect to Telegram and may slow down your connection. | - |
| `qrCodeNoGroupQrCode` | No group QR code yet | NewGroup / GroupMembers / Groups; AuthAnotherClient / QrCode |
| `qrCodeScanToAddFriend` | Scan the QR code above to add me as a friend | AuthAnotherClient / QrCode |
| `richTextComposerAddColumn` | Add column | - |
| `richTextComposerAddRow` | Add row | - |
| `richTextComposerContentPlaceholder` | Enter rich text | - |
| `richTextComposerFormatBoldMark` | B | - |
| `richTextComposerFormatItalicMark` | I | - |
| `richTextComposerFormatStrikethroughMark` | S | Exact upstream text: SecretChatTimerSeconds, CalendarWeekNameShortSaturday, CalendarWeekNameShortSunday |
| `richTextComposerFormatUnderlineMark` | U | - |
| `settingsAboutMithka` | About Mithka | - |
| `sharedMediaCacheDeleted` | Local cache deleted | ClearCache / StorageUsage; Delete / DeleteChat / DeleteAll / DeleteAllFrom |
| `sharedMediaDownloadedSize` | Downloaded {value1} | Download / Downloaded |
| `sharedMediaDownloadProgress` | Downloaded {value1} of {value2} | Download / Downloaded |
| `sharedMediaFromSource` | From {value1} | - |
| `sharedMediaNotDownloadedSize` | Not downloaded · {value1} | Download / Downloaded |
| `stickerSetDetailAddSuccess` | Sticker added | AttachSticker / ViewPackPreview |
| `stickerSetDetailRemoved` | Sticker removed | AttachSticker / ViewPackPreview; Delete / Remove |
| `stickerSetDetailTitle` | Sticker Details | AttachSticker / ViewPackPreview |
| `tabFriendMoments` | Friends' Moments | - |
| `tabMoments` | Moments | - |
| `tdMessageBoostedGroup` | Boosted this group | Message / SendMessage / SearchMessages; NewGroup / GroupMembers / Groups |
| `tdMessageLastSeenMonthDay` | Last seen {value1}/{value2} | Message / SendMessage / SearchMessages |
| `tdMessageLastSeenTodayTime` | Last seen today at {value1}:{value2} | Message / SendMessage / SearchMessages |
| `tdMessageLastSeenYearMonthDay` | Last seen {value1}/{value2}/{value3} | Message / SendMessage / SearchMessages |
| `tdMessageLastSeenYesterdayTime` | Last seen yesterday at {value1}:{value2} | Message / SendMessage / SearchMessages |
| `tdMessagePaidMessagePriceChanged` | Message price changed to {value1} Stars | Message / SendMessage / SearchMessages; MessageLockedStars / Stars |
| `tdMessagePaidMessagesDisabled` | Paid messages turned off | Message / SendMessage / SearchMessages |
| `tdMessagePaidMessageSettingsChanged` | [Paid message settings changed] | Message / SendMessage / SearchMessages |
| `themeApplePingFangFamily` | Apple / PingFang | ThemeDay / ThemeDark / ThemeNight |
| `themeGroupAssistantSecondPageFirst` | First on second screen | NewGroup / GroupMembers / Groups; ThemeDay / ThemeDark / ThemeNight |
| `themeGroupAssistantSortByTime` | Sort by time | NewGroup / GroupMembers / Groups; ThemeDay / ThemeDark / ThemeNight |
| `themeGroupAssistantTopCollapsed` | Top collapsed | NewGroup / GroupMembers / Groups; ThemeDay / ThemeDark / ThemeNight |
| `themePingFangHongKong` | PingFang Hong Kong [HK] | ThemeDay / ThemeDark / ThemeNight |
| `themePingFangSimplifiedChinese` | PingFang Simplified Chinese [CN] | ThemeDay / ThemeDark / ThemeNight |
| `themePingFangTraditionalChinese` | PingFang Traditional Chinese [TW] | ThemeDay / ThemeDark / ThemeNight |
| `themeSystemMonospace` | System monospace | ThemeDay / ThemeDark / ThemeNight |
| `themeUnreadChatCount` | Unread chats | SearchAllChatsShort / SelectChat; ThemeDay / ThemeDark / ThemeNight |
| `themeUnreadCountCapAt99` | Show 99+ above 99 | ThemeDay / ThemeDark / ThemeNight |
| `themeUnreadCountShowActual` | Show actual count above 99 | ThemeDay / ThemeDark / ThemeNight |
| `topicChatAwaitingYourPost` | Waiting for your post | SearchAllChatsShort / SelectChat; Topics / NoTopics / CreateTopicsPermission |
| `topicChatBeKindPrompt` | Be kind | SearchAllChatsShort / SelectChat; Topics / NoTopics / CreateTopicsPermission |
| `topicChatChannelNumber` | Channel No. {value1} | SearchAllChatsShort / SelectChat; Channel / ChannelSettings / ChannelMembers; Topics / NoTopics / CreateTopicsPermission |
| `topicChatComposerPlaceholder` | Share a thought, caption, or link | SearchAllChatsShort / SelectChat; Topics / NoTopics / CreateTopicsPermission; SharedLinksTab / ShareLink; AddCaption / HideCaption |
| `topicChatGroupChatTitle` | Topic Group Chat | SearchAllChatsShort / SelectChat; NewGroup / GroupMembers / Groups; Topics / NoTopics / CreateTopicsPermission |
| `topicChatLeaveChannelConfirm` | Leaving "{value1}" will delete this topic channel. Continue? | SearchAllChatsShort / SelectChat; Channel / ChannelSettings / ChannelMembers; Topics / NoTopics / CreateTopicsPermission; Delete / DeleteChat / DeleteAll / DeleteAllFrom |
| `topicChatLikeCommentSummary` | {value1} likes · {value2} comments | SearchAllChatsShort / SelectChat; CommentsNoNumber / RepliesTitle; Topics / NoTopics / CreateTopicsPermission |
| `topicChatMostRelevant` | Most Relevant | SearchAllChatsShort / SelectChat; Topics / NoTopics / CreateTopicsPermission |
| `topicChatMuteMessagesToggle` | Mute Messages | Message / SendMessage / SearchMessages; SearchAllChatsShort / SelectChat; Topics / NoTopics / CreateTopicsPermission |
| `topicChatNoMoreContent` | No more content | SearchAllChatsShort / SelectChat; Topics / NoTopics / CreateTopicsPermission |
| `topicChatPinnedPrefix` | Pinned \|  | SearchAllChatsShort / SelectChat; Topics / NoTopics / CreateTopicsPermission; PinnedMessages / PinMessage |
| `translationInternalNoExternalApi` | Internal translation does not use an external API | TranslateMessage |
| `translationLibreTranslateUrlRequired` | Set the LibreTranslate URL first | TranslateMessage |
| `translationMlKitLocal` | ML Kit (local) | TranslateMessage |
| `translationNativeCancelledOrTimedOut` | Native translation was canceled or timed out | TranslateMessage |
| `translationNativeNoExternalApi` | Native translation does not use an external API | TranslateMessage |
| `translationServiceInvalidResponse` | Invalid response format from translation service | TranslateMessage |
| `translationServiceReturnedStatus` | Translation service returned {value1} | TranslateMessage |
| `translationServiceUrlInvalid` | Invalid translation service URL | TranslateMessage |
| `translationSettingsService` | Translation Service | TranslateMessage |
| `translationSettingsTargetLanguage` | Target Language | TranslateMessage; SettingsLanguage |
| `translationSystem` | System Translation | TranslateMessage |
| `translationTelegram` | Telegram Translation | TranslateMessage |
| `updateNewVersionFound` | New Version Available | - |
| `videoPlayerSplitScreen` | Split Screen | AttachVideo / Videos |
| `videoPlayerStreamingWhileDownloading` | Streaming while downloading | AttachVideo / Videos |
| `videoPlayerToggleDisplayMode` | Switch display mode | AttachVideo / Videos |
| `vipBadgeLabel` | VIP | - |
