# Telegram Localization Mapping Review

Generated for the Telegram language-pack migration. Mapped strings use Telegram language-pack keys at runtime; unmapped strings keep Mithka localizations until reviewed.

- Total app strings: 989
- Mapped to Telegram keys: 531
- Unmapped app strings: 458

## Unmapped Strings

| Mithka key | English text | Similar Telegram concept candidates |
| --- | --- | --- |
| `aboutTitle` | About | - |
| `aboutVersion` | Version {value1} | - |
| `aboutWebsite` | Website | - |
| `accountBackupCopied` | Pyrogram session copied | CurrentSession / OtherSessions |
| `accountBackupCopyPyrogramMessage` | This copies the active Telegram authorization session to the clipboard. Anyone with this string can sign in as this account. | Copy; Message / SendMessage / SearchMessages; CurrentSession / OtherSessions |
| `accountBackupCopyPyrogramSession` | Copy Pyrogram session | Copy; CurrentSession / OtherSessions |
| `accountBackupCopyPyrogramTitle` | Copy Pyrogram session? | Copy; CurrentSession / OtherSessions |
| `accountBackupCreate` | Back up current account to Keychain | Create / NewGroup / ChannelAlertCreate2 |
| `accountBackupDeleteMessage` | This removes the saved session from Keychain. The Telegram session is not revoked. | Delete / DeleteChat / DeleteAll / DeleteAllFrom; Message / SendMessage / SearchMessages; CurrentSession / OtherSessions; Save |
| `accountBackupDeleteInvalidSession` | Delete Saved Session | Delete / DeleteChat / DeleteAll / DeleteAllFrom; CurrentSession / OtherSessions; Save |
| `accountBackupDeleteTitle` | Delete saved session? | Delete / DeleteChat / DeleteAll / DeleteAllFrom; CurrentSession / OtherSessions; Save |
| `accountBackupEmpty` | No account sessions are backed up yet. | CurrentSession / OtherSessions |
| `accountBackupEnabled` | Back up accounts | - |
| `accountBackupFreshSessionCreate` | Create New Session | CurrentSession / OtherSessions; Create / NewGroup / ChannelAlertCreate2 |
| `accountBackupFreshSessionInteractive` | Continue the login step to finish creating the new session. | CurrentSession / OtherSessions; BotAuthLogin / AuthAnotherClient |
| `accountBackupFreshSessionMessage` | The restored session is ready. To avoid using the same Telegram session on multiple devices, Mithka can create a new session from it with QR login. Telegram may ask for your two-step verification password. | Message / SendMessage / SearchMessages; CurrentSession / OtherSessions; Devices / CurrentSession / OtherSessions; TwoStepVerification / Password; BotAuthLogin / AuthAnotherClient |
| `accountBackupFreshSessionReady` | Created a new session in slot {value1} | CurrentSession / OtherSessions |
| `accountBackupFreshSessionTitle` | Create a new session? | CurrentSession / OtherSessions; Create / NewGroup / ChannelAlertCreate2 |
| `accountBackupFreshSessionUseRestored` | Use Restored Session | CurrentSession / OtherSessions |
| `accountBackupFreshSessionWaiting` | Creating the new session... | CurrentSession / OtherSessions |
| `accountBackupInvalidImportedMessage` | This session string is no longer valid or may have been revoked. Please export a fresh session from a logged-in device. | Message / SendMessage / SearchMessages; CurrentSession / OtherSessions; Devices / CurrentSession / OtherSessions |
| `accountBackupInvalidMessage` | The saved session for {value1} is no longer valid or may have been revoked. Delete this saved session from Keychain? | Delete / DeleteChat / DeleteAll / DeleteAllFrom; Message / SendMessage / SearchMessages; CurrentSession / OtherSessions; Save |
| `accountBackupInvalidTitle` | Session no longer valid | CurrentSession / OtherSessions |
| `accountBackupImported` | Imported to account slot {value1} | - |
| `accountBackupIOSOnly` | Account backup is available on iOS only. | - |
| `accountBackupLoadPyrogramConfirm` | Load Session | CurrentSession / OtherSessions |
| `accountBackupLoadPyrogramMessage` | Paste a Pyrogram-compatible Telegram session string. The session will be imported locally as an account if it is still valid. | Paste; Message / SendMessage / SearchMessages; CurrentSession / OtherSessions |
| `accountBackupLoadPyrogramPlaceholder` | Pyrogram session string | CurrentSession / OtherSessions |
| `accountBackupLoadPyrogramSession` | Load Pyrogram session | CurrentSession / OtherSessions |
| `accountBackupLoadPyrogramTitle` | Load Pyrogram session | CurrentSession / OtherSessions |
| `accountBackupNotice` | Only the TDLib session file is stored in the device Keychain. Message databases, media, logs, and caches are not backed up. To transfer this Keychain item to a new device, restore from an encrypted device backup. | Message / SendMessage / SearchMessages; AttachDocument / SharedFilesTab; CurrentSession / OtherSessions; Devices / CurrentSession / OtherSessions; Restore |
| `accountBackupRestoreAccount` | Restore saved account | Restore; Save |
| `accountBackupRestored` | Restored to account slot {value1} | - |
| `accountBackupRestoreMessage` | This imports the saved session as a new account. The session must still be active on Telegram servers. | Message / SendMessage / SearchMessages; CurrentSession / OtherSessions; Restore; Save |
| `accountBackupRestoreTitle` | Restore saved session? | CurrentSession / OtherSessions; Restore; Save |
| `accountBackupSaved` | Session saved ({value1}) | CurrentSession / OtherSessions; Save |
| `accountBackupSessions` | Saved Sessions | CurrentSession / OtherSessions; Save |
| `accountBackupTitle` | Account Backup | - |
| `accountBackupUserId` | User ID: {value1} | - |
| `addMembersDoneWithCount` | Done ({value1}) | Members / GroupMembers / ChannelMembers; Done |
| `addMembersInvitePermissionError` | Invite failed. You may not have permission. | Members / GroupMembers / ChannelMembers; AddMember / VoipGroupInviteMember; ErrorOccurred |
| `addPeopleFindGroups` | Find Groups | NewGroup / GroupMembers / Groups |
| `addPeopleFindPeople` | Find People | - |
| `addPeopleGroupNameOrLinkPlaceholder` | Group name/link | NewGroup / GroupMembers / Groups; SharedLinksTab / ShareLink |
| `addPeopleNoGroupsOrChannelsFound` | No groups or channels found | NewGroup / GroupMembers / Groups; Channel / ChannelSettings / ChannelMembers |
| `addPeopleNoUsersFound` | No users found | - |
| `addPeopleUsernameOrPhonePlaceholder` | Username/phone number | Username / SetUsernameHeader; Phone |
| `apiCredentialsCustomClientApi` | Custom Client API | - |
| `apiCredentialsDescription` | Off by default. When enabled, fill in your own Telegram client API credentials; they take effect on the next launch or after signing in again. Acceleration stays off until every field is filled in. | Default |
| `apiCredentialsTitle` | Video and Download Acceleration | AttachVideo / Videos; Download / Downloaded |
| `appIconBlueGradient` | Blue Gradient | - |
| `appIconChangeFailed` | Failed to change app icon | ErrorOccurred |
| `appIconPixel` | 8-bit Pixel | - |
| `appIconPurpleGradient` | Purple Gradient | - |
| `appIconUnsupported` | This platform or launcher may not support changing the app icon. | - |
| `appIconWhite` | Pure White | - |
| `appearanceAddFont` | Add Font | FontSize |
| `appearanceAddTextFont` | Add Text Font | FontSize |
| `appearanceCacheCleaned` | Cleaned | ClearCache / StorageUsage |
| `appearanceCacheFiles` | Cache Files | AttachDocument / SharedFilesTab; ClearCache / StorageUsage |
| `appearanceCacheRefreshed` | Refreshed | ClearCache / StorageUsage |
| `appearanceCapUnreadCountAt99` | Show 99+ after 99 | - |
| `appearanceChatList` | Chat List | SearchAllChatsShort / SelectChat |
| `appearanceChatView` | Chat View | SearchAllChatsShort / SelectChat |
| `appearanceCleanableSize` | Cleanable | - |
| `appearanceCleanUnusedFonts` | Clean Unused Fonts | - |
| `appearanceClearTextFonts` | Clear Text Fonts | - |
| `appearanceColor` | Color | NotificationsLedColor |
| `appearanceDisplay` | Display | - |
| `appearanceDownloadFailed` | Download failed | Download / Downloaded; ErrorOccurred |
| `appearanceEmojiFont` | Emoji Font | FontSize; Emoji1..Emoji7 / SetEmojiStatus |
| `appearanceEmojiFontCatalogDescription` | The font list comes from the iebb/emojifonts manifest. Selected fonts are downloaded from GitHub Releases. Previews come from Emojipedia. | Download / Downloaded; FontSize; Emoji1..Emoji7 / SetEmojiStatus |
| `appearanceFileCount` | {value1} | AttachDocument / SharedFilesTab |
| `appearanceFont` | Font | FontSize |
| `appearanceFontCache` | Font Cache | ClearCache / StorageUsage; FontSize |
| `appearanceFontCacheDescription` | Manages only runtime-downloaded Google font caches. Files used by the current font chain, monospace font, and emoji font are kept. | AttachDocument / SharedFilesTab; Download / Downloaded; ClearCache / StorageUsage; FontSize; Emoji1..Emoji7 / SetEmojiStatus |
| `appearanceFontChainDescription` | Text fonts are applied in order across the interface. The emoji font is preferred for emoji. The monospace font is used for code blocks. | FontSize; Emoji1..Emoji7 / SetEmojiStatus |
| `appearanceFontDownloadFailedName` | {value1} · Download failed | Download / Downloaded; FontSize; ErrorOccurred |
| `appearanceFontInUse` | In Use | FontSize |
| `appearanceFontLoadFailed` | Failed to load | FontSize; ErrorOccurred |
| `appearanceFontUnused` | Unused | FontSize |
| `appearanceGoogleDownloaded` | Google downloaded | Download / Downloaded |
| `appearanceGroupAssistantPosition` | Group Assistant Position | NewGroup / GroupMembers / Groups |
| `appearanceHidePhoneInSidebar` | Hide Phone Number in Sidebar | Phone |
| `appearanceInterfaceSize` | Interface Size | - |
| `appearanceInUseSize` | In Use | - |
| `appearanceManage` | Manage | - |
| `appearanceMergeConsecutiveImages` | Merge Consecutive Images | AttachPhoto / SharedMediaTab |
| `appearanceMode` | Mode | - |
| `appearanceMonospaceFont` | Monospace Font | FontSize |
| `appearanceNoCleanableFonts` | Nothing to clean | - |
| `appearanceNoDownloadedFontCache` | No downloaded font cache. | Download / Downloaded; ClearCache / StorageUsage; FontSize |
| `appearanceNoMatchingFonts` | No matching fonts | - |
| `appearanceRefreshCacheList` | Refresh Cache List | ClearCache / StorageUsage |
| `appearanceRoundGroupAvatars` | Show Group Avatars as Circles | NewGroup / GroupMembers / Groups |
| `appearanceSearchFont` | Search fonts | Search / SearchMessages / NoResult; FontSize |
| `appearanceShowChatFiltersOnTop` | Show Chat Filters at Top | SearchAllChatsShort / SelectChat |
| `appearanceShowChatListSearch` | Show Chat List Search | Search / SearchMessages / NoResult; SearchAllChatsShort / SelectChat |
| `appearanceShowEditAndReadMarks` | Show Edit and Read Marks | - |
| `appearanceShowGroupMemberTitles` | Show Group Member Titles | NewGroup / GroupMembers / Groups; Members / GroupMembers / ChannelMembers |
| `appearanceShowPremiumNameColor` | Show Premium Name Color | TelegramPremiumShort |
| `appearanceShowPremiumStatusEmoji` | Show Premium Status Emoji | Emoji1..Emoji7 / SetEmojiStatus; TelegramPremiumShort |
| `appearanceShowUnreadChatCount` | Show Unread Chat Count | SearchAllChatsShort / SelectChat |
| `appearanceSize` | Size | - |
| `appearanceSystemEmojiFont` | System emoji font | FontSize; Emoji1..Emoji7 / SetEmojiStatus |
| `appearanceTextFont` | Text Font | FontSize |
| `appearanceTextFontOrderHint` | Text fonts are applied in order. Characters not covered continue using the system font. | FontSize |
| `appearanceTextFontUnsetHint` | No text font set. Using the system default. | FontSize; Default |
| `appearanceTotalSize` | Total Size | - |
| `appearanceUnreadBadge` | Unread Badge | - |
| `appLocaleArabic` | العربية | - |
| `appLocaleEnglish` | English | LanguageName; English; LanguageNameInEnglish |
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
| `archivedChatsGroupAssistant` | Group Assistant | SearchAllChatsShort / SelectChat; NewGroup / GroupMembers / Groups |
| `audioSearchFetchingSource` | Fetching source… | Search / SearchMessages / NoResult; AttachAudio / AttachMusic |
| `authCodeSent` | Verification code sent | - |
| `authCodeSentByFlashCall` | You will receive a flash call | Call / VideoCall / VoipConnecting |
| `authCodeSentByPhoneCall` | You’ll receive a phone call with the verification code | Call / VideoCall / VoipConnecting; Phone |
| `authCodeSentBySms` | The verification code was sent by SMS | - |
| `authCodeSentToTelegramDevices` | The verification code was sent to your other Telegram devices | Devices / CurrentSession / OtherSessions |
| `authInvalidVerificationCode` | Incorrect verification code | - |
| `autoDeleteDescription` | New messages will be automatically deleted from the chat after the set time. | Delete / DeleteChat / DeleteAll / DeleteAllFrom; Message / SendMessage / SearchMessages; SearchAllChatsShort / SelectChat |
| `callIncomingCallInvite` | invited you to a {value1} call | Call / VideoCall / VoipConnecting; AddMember / VoipGroupInviteMember |
| `callWaitingForInviteAccept` | Waiting for the other person to accept… | Call / VideoCall / VoipConnecting; AddMember / VoipGroupInviteMember |
| `chatAdminsOnlyPosting` | Only admins can post | SearchAllChatsShort / SelectChat |
| `chatAllMembersMuted` | All members are muted | SearchAllChatsShort / SelectChat; Members / GroupMembers / ChannelMembers |
| `chatAndOthersCount` |  and {value1} others | SearchAllChatsShort / SelectChat |
| `chatButtonUnsupported` | This button isn’t supported yet | SearchAllChatsShort / SelectChat |
| `chatContactCallsOnly` | Calls are only supported with contacts | SearchAllChatsShort / SelectChat; Contacts / AddContactChat / SelectContact; Call / VideoCall / VoipConnecting |
| `chatDeleteActionsFailed` | Could not apply action: {value1} | Delete / DeleteChat / DeleteAll / DeleteAllFrom; SearchAllChatsShort / SelectChat; ErrorOccurred |
| `chatDeleteSelectedMessagesConfirmation` | Delete the selected {value1} messages? | Delete / DeleteChat / DeleteAll / DeleteAllFrom; Message / SendMessage / SearchMessages; SearchAllChatsShort / SelectChat |
| `chatBlockUserMessage` | Block this sender, report the message for review, and remove their messages from this chat immediately? | Delete / Remove; BlockUser / BlockedUsers; ReportChat / ReportChatSent; Message / SendMessage / SearchMessages; SearchAllChatsShort / SelectChat |
| `chatForwardedToName` | Forwarded to {value1} | SearchAllChatsShort / SelectChat |
| `chatForwardFailed` | Forward failed: {value1} | Forward / ForwardTo; SearchAllChatsShort / SelectChat; ErrorOccurred |
| `chatForwardProtected` | This message is protected and can’t be forwarded | Forward / ForwardTo; Message / SendMessage / SearchMessages; SearchAllChatsShort / SelectChat |
| `chatForwardRemoveCaption` | Remove caption | Forward / ForwardTo; Delete / Remove; SearchAllChatsShort / SelectChat; AddCaption |
| `chatForwardRemoveSender` | Remove sender | Forward / ForwardTo; Delete / Remove; SearchAllChatsShort / SelectChat |
| `chatInfoClearHistoryDescription` | This deletes the local chat history but does not leave the chat. | SearchAllChatsShort / SelectChat; LeaveMegaMenu / LeaveChannel |
| `chatInfoClearHistoryIrreversibleWarning` | After clearing, history on this device can’t be recovered. | SearchAllChatsShort / SelectChat; Devices / CurrentSession / OtherSessions |
| `chatInfoConfirmAgain` | Confirm again | SearchAllChatsShort / SelectChat |
| `chatInfoDisableExplicitFolderWarning` | Turning off explicit folders will remove this chat. If it still matches automatic folder rules, it will be added to the exclusions list. | Delete / Remove; SearchAllChatsShort / SelectChat; SettingsFolders / FilterNew / FilterNameHeader |
| `chatInfoFolderName` | Folder {value1} | SearchAllChatsShort / SelectChat; SettingsFolders / FilterNew / FilterNameHeader |
| `chatInfoGroupAlbum` | Group album | SearchAllChatsShort / SelectChat; NewGroup / GroupMembers / Groups; Album |
| `chatInfoGroupApps` | Group apps | SearchAllChatsShort / SelectChat; NewGroup / GroupMembers / Groups |
| `chatInfoGroupChat` | Group chat | SearchAllChatsShort / SelectChat; NewGroup / GroupMembers / Groups |
| `chatInfoGroupId` | Group ID: {value1} | SearchAllChatsShort / SelectChat; NewGroup / GroupMembers / Groups |
| `chatInfoMoveToGroupAssistant` | Move to Group Assistant | SearchAllChatsShort / SelectChat; NewGroup / GroupMembers / Groups |
| `chatInfoPinFailedWithReason` | Pin failed: {value1} | PinMessage / PinToTop / PinnedMessages; SearchAllChatsShort / SelectChat; ErrorOccurred |
| `chatInfoTitle` | Chat Info | SearchAllChatsShort / SelectChat |
| `chatInlineSwitchButtonUnsupported` | Inline switch buttons aren’t supported yet | SearchAllChatsShort / SelectChat |
| `chatListAddFriendOrGroup` | Add friend/group | SearchAllChatsShort / SelectChat; NewGroup / GroupMembers / Groups |
| `chatListBlockedPlaceholder` | [Blocked] | BlockedUsers; SearchAllChatsShort / SelectChat |
| `chatMeLabel` | Me | SearchAllChatsShort / SelectChat |
| `chatMemberCount` | {value1} members | SearchAllChatsShort / SelectChat; Members / GroupMembers / ChannelMembers |
| `chatMembersRemoveMemberConfirmation` | Remove {value1} from the group? | Delete / Remove; SearchAllChatsShort / SelectChat; NewGroup / GroupMembers / Groups; Members / GroupMembers / ChannelMembers |
| `chatMembersRemoveMemberTitle` | Remove Member | Delete / Remove; SearchAllChatsShort / SelectChat; Members / GroupMembers / ChannelMembers |
| `chatMessageRequired` | Message can’t be empty | Message / SendMessage / SearchMessages; SearchAllChatsShort / SelectChat |
| `chatMessagesSavedCount` | Saved {value1} messages | Message / SendMessage / SearchMessages; SearchAllChatsShort / SelectChat; Save |
| `chatMoreActionsUnsupported` | More actions aren’t supported yet | SearchAllChatsShort / SelectChat |
| `chatReportMessage` | Report this message as objectionable or abusive content? | ReportChat / ReportChatSent; Message / SendMessage / SearchMessages; SearchAllChatsShort / SelectChat |
| `chatPeopleDoingAction` | {value1} people active… | SearchAllChatsShort / SelectChat |
| `chatPeopleTyping` | {value1} people are typing… | SearchAllChatsShort / SelectChat |
| `chatRestrictedTelegramTosMessage` | This group can’t be displayed because it violated Telegram's Terms of Service. You can go back or leave the group. | Message / SendMessage / SearchMessages; SearchAllChatsShort / SelectChat; NewGroup / GroupMembers / Groups; LeaveMegaMenu / LeaveChannel |
| `chatRestrictedTitle` | Safety notice | SearchAllChatsShort / SelectChat |
| `chatSavedToSavedMessages` | Saved to Saved Messages | Message / SendMessage / SearchMessages; SearchAllChatsShort / SelectChat; Save |
| `chatSelectedMessagesCount` | {value1} messages selected | Message / SendMessage / SearchMessages; SearchAllChatsShort / SelectChat |
| `chatsSearchPublicGroupsAndChannels` | Public groups/channels | Search / SearchMessages / NoResult; SearchAllChatsShort / SelectChat; NewGroup / GroupMembers / Groups; Channel / ChannelSettings / ChannelMembers |
| `chatStickerAddSuccess` | Added to emoji | SearchAllChatsShort / SelectChat; Emoji1..Emoji7 / SetEmojiStatus; AttachSticker / ViewPackPreview |
| `chatActionWatchingAnimations` | watching animations… | SearchAllChatsShort / SelectChat |
| `chatUserFallbackName` | User {value1} | SearchAllChatsShort / SelectChat |
| `chatUserLeftGroup` | {value1} left the group | SearchAllChatsShort / SelectChat; NewGroup / GroupMembers / Groups |
| `chatUsersJoinedGroup` | {value1}{value2} joined the group | SearchAllChatsShort / SelectChat; NewGroup / GroupMembers / Groups |
| `chatUserDoingAction` | {value1} is {value2} | SearchAllChatsShort / SelectChat |
| `chatYouAreMuted` | You are muted | SearchAllChatsShort / SelectChat |
| `chatYouWereRemovedFromGroup` | You were removed from this group | SearchAllChatsShort / SelectChat; NewGroup / GroupMembers / Groups |
| `checklistComposerPremiumLimitHint` | Up to 30 items · Creating checklists requires Telegram Premium | Todo / TodoTitle / AttachChecklist; TelegramPremiumShort |
| `checklistComposerTaskLabel` | Task {value1} | Todo / TodoTitle / AttachChecklist |
| `checklistComposerTitleLabel` | Checklist title | Todo / TodoTitle / AttachChecklist |
| `commonUiGroupOwner` | Group owner | NewGroup / GroupMembers / Groups |
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
| `composerPaidMessageCost` | Sending this message costs {value1} Stars. | Message / SendMessage / SearchMessages |
| `composerPastedImageReadFailed` | Could not read pasted image | AttachPhoto / SharedMediaTab; ErrorOccurred |
| `composerRichText` | Rich text | - |
| `composerRichTextMessageTitle` | Rich text message | Message / SendMessage / SearchMessages |
| `composerSendPaidMessageQuestion` | Send paid message? | Message / SendMessage / SearchMessages |
| `contactsFriends` | Friends | Contacts / AddContactChat / SelectContact |
| `contactsNoGroupChats` | No group chats yet | SearchAllChatsShort / SelectChat; NewGroup / GroupMembers / Groups; Contacts / AddContactChat / SelectContact |
| `createGroupStartGroupChat` | Start group chat | SearchAllChatsShort / SelectChat; NewGroup / GroupMembers / Groups; Create / NewGroup / ChannelAlertCreate2 |
| `editProfileAnimatedAvatarDescription` | Use a short video as your avatar | AttachVideo / Videos; MyProfile / UserBio |
| `editProfileBirthDay` | {value1} | MyProfile / UserBio |
| `editProfileBirthMonth` | {value1} | MyProfile / UserBio |
| `editProfileBirthYear` | {value1} | MyProfile / UserBio |
| `editProfileChooseAvatarType` | Choose avatar type | MyProfile / UserBio |
| `editProfileNameColor` | Name color | MyProfile / UserBio |
| `editProfileNameColorDescription` | Used for your name and message sidebar. | Message / SendMessage / SearchMessages; MyProfile / UserBio |
| `editProfileNoBirthYear` | No year | MyProfile / UserBio |
| `editProfileProfileColor` | Profile color | MyProfile / UserBio |
| `editProfileProfileColorDescription` | Used for your profile page background. | MyProfile / UserBio |
| `editProfileStaticAvatarDescription` | Crop and upload a still image | AttachPhoto / SharedMediaTab; MyProfile / UserBio |
| `editProfileTitle` | Edit profile | MyProfile / UserBio |
| `editProfileUsernameUnavailable` | Username unavailable | Username / SetUsernameHeader; MyProfile / UserBio |
| `editProfileUsernameUnsetHandle` | @not set | Username / SetUsernameHeader; MyProfile / UserBio |
| `emojiPreviewFaceWithTearsOfJoy` | Face with tears of joy | Emoji1..Emoji7 / SetEmojiStatus |
| `emojiStatusNoAvailableStatuses` | No available statuses in this emoji pack | Emoji1..Emoji7 / SetEmojiStatus |
| `developerModePiPBoundsOverlay` | PiP bounds overlay | - |
| `developerModePiPBoundsOverlayDescription` | Shows the app-level PiP frame and viewport size to diagnose rotation, clipping, or overlay coverage. | - |
| `developerModeTitle` | Developer Mode | - |
| `developerModeUnlocked` | Developer Mode unlocked | - |
| `featureBottomTabs` | Bottom tabs | - |
| `fileDetailDownloadProgress` | Downloading file… ({value1}/{value2}) | AttachDocument / SharedFilesTab; Download / Downloaded |
| `generalCacheSize` | Cache size | ClearCache / StorageUsage |
| `generalOpenChatAtLatestMessage` | Open chats at latest message | Message / SendMessage / SearchMessages; SearchAllChatsShort / SelectChat; Open |
| `generalSendMessageWithEnter` | Send messages with Enter | Message / SendMessage / SearchMessages |
| `groupManagementAdminApprovalRequired` | Admin approval required | NewGroup / GroupMembers / Groups |
| `groupManagementBasicSection` | Basic management | NewGroup / GroupMembers / Groups |
| `groupManagementEditable` | Editable | NewGroup / GroupMembers / Groups |
| `groupManagementJoinBeforePosting` | Join before posting | NewGroup / GroupMembers / Groups; JoinGroup / RequestToJoin / ChannelJoinRequestSent |
| `groupManagementJoinSection` | Join settings | NewGroup / GroupMembers / Groups; JoinGroup / RequestToJoin / ChannelJoinRequestSent |
| `groupManagementLogApprovedJoinRequest` | Approved join request | NewGroup / GroupMembers / Groups; JoinGroup / RequestToJoin / ChannelJoinRequestSent |
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
| `groupManagementLogDeletedInviteLink` | Deleted invite link | NewGroup / GroupMembers / Groups; SharedLinksTab / ShareLink; AddMember / VoipGroupInviteMember |
| `groupManagementLogDeletedMessage` | Deleted message | Message / SendMessage / SearchMessages; NewGroup / GroupMembers / Groups |
| `groupManagementLogDeletedTopic` | Deleted topic | NewGroup / GroupMembers / Groups; Topics / NoTopics / CreateTopicsPermission |
| `groupManagementLogEditedInviteLink` | Edited invite link | NewGroup / GroupMembers / Groups; SharedLinksTab / ShareLink; AddMember / VoipGroupInviteMember |
| `groupManagementLogEditedMessage` | Edited message | Message / SendMessage / SearchMessages; NewGroup / GroupMembers / Groups |
| `groupManagementLogEditedTopic` | Edited topic | NewGroup / GroupMembers / Groups; Topics / NoTopics / CreateTopicsPermission |
| `groupManagementLogEmpty` | No management log yet | NewGroup / GroupMembers / Groups |
| `groupManagementLogEndedVideoChat` | Ended video chat | SearchAllChatsShort / SelectChat; NewGroup / GroupMembers / Groups; AttachVideo / Videos |
| `groupManagementLogGenericAdminAction` | Performed an admin action | NewGroup / GroupMembers / Groups |
| `groupManagementLogInvitedMember` | Invited member | NewGroup / GroupMembers / Groups; Members / GroupMembers / ChannelMembers |
| `groupManagementLogJoinedByInviteLink` | Joined via invite link | NewGroup / GroupMembers / Groups; SharedLinksTab / ShareLink; AddMember / VoipGroupInviteMember |
| `groupManagementLogJoinedGroup` | Joined the group | NewGroup / GroupMembers / Groups |
| `groupManagementLogLeftGroup` | Left the group | NewGroup / GroupMembers / Groups |
| `groupManagementLogNoPermission` | You do not have permission to view the group management log | NewGroup / GroupMembers / Groups |
| `groupManagementLogRevokedInviteLink` | Revoked invite link | NewGroup / GroupMembers / Groups; SharedLinksTab / ShareLink; AddMember / VoipGroupInviteMember |
| `groupManagementLogStartedVideoChat` | Started video chat | SearchAllChatsShort / SelectChat; NewGroup / GroupMembers / Groups; AttachVideo / Videos |
| `groupManagementMembersSection` | Member Management | NewGroup / GroupMembers / Groups; Members / GroupMembers / ChannelMembers |
| `groupManagementNotSet` | Not set | NewGroup / GroupMembers / Groups |
| `groupManagementPermissionEditGroupInfo` | Edit group info | NewGroup / GroupMembers / Groups |
| `groupManagementPermissionSendFiles` | Send files | NewGroup / GroupMembers / Groups; AttachDocument / SharedFilesTab |
| `groupManagementPermissionSendMusic` | Send music | NewGroup / GroupMembers / Groups; AttachMusic / SharedMusicTab |
| `groupManagementPermissionSendPhotos` | Send photos | NewGroup / GroupMembers / Groups; AttachPhoto / SharedMediaTab |
| `groupManagementPermissionSendVideoMessages` | Send video messages | Message / SendMessage / SearchMessages; NewGroup / GroupMembers / Groups; AttachVideo / Videos |
| `groupManagementPermissionSendVideos` | Send videos | NewGroup / GroupMembers / Groups; AttachVideo / Videos |
| `groupManagementPermissionSendVoice` | Send voice messages | Message / SendMessage / SearchMessages; NewGroup / GroupMembers / Groups; AttachAudio / VoiceMessages |
| `groupManagementPostingPermissions` | Posting Permissions | NewGroup / GroupMembers / Groups |
| `imageEditObscure` | Obscure | AttachPhoto / SharedMediaTab |
| `imageEditTitle` | Edit Image | AttachPhoto / SharedMediaTab |
| `keywordBlockerDescription` | After you add keywords, matching messages will be hidden in chats and will not trigger local notifications. Supports plain keywords, re:regex, regex:regex, and /regex/i. Remote lists use one rule per line; lines starting with # or // are comments. | CommentsNoNumber / RepliesTitle; Message / SendMessage / SearchMessages; SearchAllChatsShort / SelectChat; Notifications / NotificationsPrivateChats |
| `keywordBlockerInputPlaceholder` | Enter keyword | - |
| `keywordBlockerListUrl` | Keyword list URL | - |
| `keywordBlockerAddFromMessageTitle` | Block keyword | BlockUser / BlockedUsers; Message / SendMessage / SearchMessages |
| `keywordBlockerRuleAdded` | Blocked keyword: {value1} | BlockedUsers |
| `keywordBlockerRulesAdded` | Added {value1} rules | - |
| `keywordBlockerRulesUpToDate` | Rules are up to date | - |
| `keywordBlockerTitle` | Keyword Blocker | - |
| `languageMithkaLanguage` | Mithka language | SettingsLanguage |
| `languageTelegramFollowMithka` | Follow Mithka language | SettingsLanguage |
| `languageTelegramLanguage` | Telegram language | SettingsLanguage |
| `languageTelegramOfficial` | Official | SettingsLanguage |
| `languageTelegramUsing` | Using {value1} | SettingsLanguage |
| `linkHandlerQrLoginWarning` | This link can approve another device signing in to your Telegram account. Make sure it is you signing in. | SharedLinksTab / ShareLink; Devices / CurrentSession / OtherSessions; BotAuthLogin / AuthAnotherClient; AuthAnotherClient |
| `linkHandlerUnsupportedTelegramLink` | Opening this Telegram link is not supported yet | SharedLinksTab / ShareLink |
| `listSeparator` | ,  | - |
| `loginBackToAccount` | Back to {value1} | BotAuthLogin / AuthAnotherClient |
| `loginBackToPreviousAccount` | Back to previous account | BotAuthLogin / AuthAnotherClient |
| `loginCodeSentByEmail` | Enter the code sent to your email. | BotAuthLogin / AuthAnotherClient |
| `loginCodeSentByFirebase` | Enter the code from the system verification prompt. | BotAuthLogin / AuthAnotherClient |
| `loginCodeSentByFlashCall` | Enter the code from the incoming call matching {value1}. | Call / VideoCall / VoipConnecting; BotAuthLogin / AuthAnotherClient |
| `loginCodeSentByFragment` | Enter the code from Fragment. | BotAuthLogin / AuthAnotherClient |
| `loginCodeSentByMissedCall` | Enter the last {value2} digits of the missed call from {value1}. | Call / VideoCall / VoipConnecting; BotAuthLogin / AuthAnotherClient |
| `loginCodeSentByPhoneCall` | Enter the code from the phone call to {value1}. | Call / VideoCall / VoipConnecting; BotAuthLogin / AuthAnotherClient; Phone |
| `loginCodeSentBySms` | Enter the SMS code sent to {value1}. | BotAuthLogin / AuthAnotherClient |
| `loginCodeWillBeSentToNumber` | We will send a one-time login code to this number | BotAuthLogin / AuthAnotherClient |
| `loginCompleteRegistration` | Complete registration | BotAuthLogin / AuthAnotherClient |
| `loginConfigureCustomApi` | Configure custom API | BotAuthLogin / AuthAnotherClient |
| `loginGetVerificationCode` | Get code | BotAuthLogin / AuthAnotherClient |
| `loginNewAccountNicknamePrompt` | This is a new account. Please enter a nickname | BotAuthLogin / AuthAnotherClient |
| `loginPasswordHint` | Password hint: {value1} | TwoStepVerification / Password; BotAuthLogin / AuthAnotherClient |
| `loginPhoneNumberWithCountryCode` | Phone number with country code | BotAuthLogin / AuthAnotherClient; Phone |
| `loginQrCodeSubtitle` | Scan this QR code with another phone already signed in to Telegram. | BotAuthLogin / AuthAnotherClient; AuthAnotherClient; Phone |
| `loginQrCodeTitle` | QR Code Login | BotAuthLogin / AuthAnotherClient; AuthAnotherClient |
| `loginReenterPhoneNumber` | Re-enter phone number | BotAuthLogin / AuthAnotherClient; Phone |
| `loginRefreshQrCode` | Refresh QR code | BotAuthLogin / AuthAnotherClient; AuthAnotherClient |
| `loginSwitchAccount` | Switch account | BotAuthLogin / AuthAnotherClient |
| `loginTelegramAccountTitle` | Log in to Telegram | BotAuthLogin / AuthAnotherClient |
| `loginTelegramApiCredentialsMissing` | Telegram API credentials are not configured | BotAuthLogin / AuthAnotherClient |
| `loginTelegramApiPortalInstructions` | (You can get them from my.telegram.org.) | BotAuthLogin / AuthAnotherClient |
| `loginTelegramApiSecretsInstructions` | Enter your own Telegram client api_id and api_hash | BotAuthLogin / AuthAnotherClient |
| `loginTermsBody` | By using this app, you must follow Telegram's Terms of Service. Mithka signs in to existing Telegram accounts and has zero tolerance for objectionable content or abusive users. You can filter messages with Keyword Blocker, report objectionable content through Telegram, and block abusive users through Telegram. Blocking removes that sender's messages from your view immediately. | BlockUser / BlockedUsers; ReportChat / ReportChatSent; Message / SendMessage / SearchMessages; SettingsFolders / FilterNoChatsToDisplay; BotAuthLogin / AuthAnotherClient |
| `loginTwoStepPassword` | Two-step verification password | TwoStepVerification / Password; BotAuthLogin / AuthAnotherClient |
| `loginVerify` | Verify | BotAuthLogin / AuthAnotherClient |
| `markdownLabel` | Markdown | - |
| `messageActionBlockKeyword` | Block keyword | BlockUser / BlockedUsers; Message / SendMessage / SearchMessages |
| `messageActionPlayMuted` | Play muted | Message / SendMessage / SearchMessages |
| `messageBubbleCallDeclinedByOther` | Declined by the other person | Message / SendMessage / SearchMessages; Call / VideoCall / VoipConnecting |
| `messageBubbleCallDuration` | Call duration {value1} | Message / SendMessage / SearchMessages; Call / VideoCall / VoipConnecting |
| `messageBubbleExpandQuote` | Expand quote | QuoteMessage; Message / SendMessage / SearchMessages |
| `messageRepliesUnavailable` | Replies are not available for this message | RepliesTitle; Message / SendMessage / SearchMessages |
| `momentsCommentPlaceholder` | Say something... | CommentsNoNumber / RepliesTitle |
| `momentsCreatePostTitle` | Create post | Create / NewGroup / ChannelAlertCreate2 |
| `momentsLiked` | Liked | - |
| `momentsLikedByCount` | Liked by {value1} | - |
| `momentsLikedByListWithOthers` | {value1}, ... and {value2} others liked this | - |
| `momentsLikeFailed` | Like failed: {value1} | ErrorOccurred |
| `momentsNewPostsCount` | {value1} new posts | - |
| `momentsNoFriendPosts` | No posts from friends yet | - |
| `momentsNoPostableChannels` | No channels available to post to | Channel / ChannelSettings / ChannelMembers |
| `momentsNoSearchableChannels` | No searchable channels | Channel / ChannelSettings / ChannelMembers |
| `momentsNotifySubscribers` | Notify subscribers | - |
| `momentsPostAction` | Post | StarsTransactionMessage |
| `momentsPostedTo` | Posted to {value1} | - |
| `momentsPublishTo` | Post to | - |
| `momentsReplied` | Replied | - |
| `momentsReplyPrefix` | Reply to {value1}:  | RepliesTitle / Reply |
| `momentsReplyToPlaceholder` | Reply to {value1}… | RepliesTitle / Reply |
| `momentsReplyToUser` | Reply to {value1} | RepliesTitle / Reply |
| `momentsReplyToUserPlaceholder` | Reply to {value1}... | RepliesTitle / Reply |
| `momentsReplyUnavailable` | Replies are not available for this post | RepliesTitle / Reply; RepliesTitle |
| `momentsSearchChannelPosts` | Search channel posts | Search / SearchMessages / NoResult; Channel / ChannelSettings / ChannelMembers |
| `momentsSearchJoinedChannelPosts` | Search posts from joined channels | Search / SearchMessages / NoResult; Channel / ChannelSettings / ChannelMembers |
| `momentsShareSomethingPlaceholder` | Share something new... | - |
| `momentsUserLiked` | {value1} liked this | - |
| `musicPlayerAddedToPlaylist` | Added to playlist | AttachMusic / SharedMusicTab |
| `musicPlayerAlreadyInPlaylist` | Already in the playlist | AttachMusic / SharedMusicTab |
| `musicPlayerQueueTitleWithCount` | Play queue ({value1}) | AttachMusic / SharedMusicTab |
| `netemoMusicLabel` | Netemo music | AttachMusic / SharedMusicTab |
| `notificationGroupMessages` | Group messages | Message / SendMessage / SearchMessages; NewGroup / GroupMembers / Groups; Notifications / NotificationsPrivateChats |
| `pollComposerQuestionRequired` | Enter a question | Poll / NewPoll / AddAnOption |
| `pollComposerSingleChoiceLimitHint` | Single choice · Up to 10 options | Poll / NewPoll / AddAnOption |
| `privacyDeleteTelegramAccountMessage` | Telegram accounts are managed by Telegram and can be set to delete automatically after a period of inactivity in Telegram settings. To delete sooner, open Telegram's official account deletion page and complete deletion directly with Telegram. | Delete / DeleteChat / DeleteAll / DeleteAllFrom; Message / SendMessage / SearchMessages; PrivacySettings / PrivacyTitle; Open |
| `privacyDeleteTelegramAccountOpen` | Open deletion page | Delete / DeleteChat / DeleteAll / DeleteAllFrom; PrivacySettings / PrivacyTitle; Open |
| `privacyDeviceApp` | App | PrivacySettings / PrivacyTitle; Devices / CurrentSession / OtherSessions |
| `privacyLoginQrAccepted` | Login approved | PrivacySettings / PrivacyTitle; BotAuthLogin / AuthAnotherClient; AuthAnotherClient |
| `privacyLoginQrInvalid` | This is not a Telegram login QR code | PrivacySettings / PrivacyTitle; BotAuthLogin / AuthAnotherClient; AuthAnotherClient |
| `privacyNoOtherDevices` | No other devices are logged in | PrivacySettings / PrivacyTitle; Devices / CurrentSession / OtherSessions |
| `privacyScanLoginQrSubtitle` | Scan the QR code shown on another Telegram login screen to approve that device. | PrivacySettings / PrivacyTitle; Devices / CurrentSession / OtherSessions; BotAuthLogin / AuthAnotherClient; AuthAnotherClient |
| `privacyTerminateSessionMessage` | Terminate {value1}? | Message / SendMessage / SearchMessages; PrivacySettings / PrivacyTitle; CurrentSession / OtherSessions |
| `profileDetailAudioVideoCall` | Audio/video call | Call / VideoCall / VoipConnecting; AttachVideo / Videos; AttachAudio / AttachMusic; MyProfile / UserBio |
| `profileDetailCardLinkCopied` | Profile card link copied | SharedLinksTab / ShareLink; MyProfile / UserBio |
| `profileDetailFeaturedPhotos` | Featured photos | AttachPhoto / SharedMediaTab; MyProfile / UserBio |
| `profileDetailMonthDayDate` | {value1}/{value2} | MyProfile / UserBio |
| `profileDetailYearMonthDate` | {value1}/{value2} | MyProfile / UserBio |
| `profileLogOutAccountConfirm` | This will revoke the Telegram session for {value1}, remove its local data, and delete its saved Keychain backup. | Delete / DeleteChat / DeleteAll / DeleteAllFrom; Delete / Remove; CurrentSession / OtherSessions; MyProfile / UserBio; Save |
| `profileRemoveAccountConfirm` | {value1} will be removed from this device. The Telegram session stays active on Telegram and can be restored from a saved backup. | Delete / Remove; CurrentSession / OtherSessions; Devices / CurrentSession / OtherSessions; MyProfile / UserBio; Save |
| `proxyDescription` | The proxy is only used to connect to Telegram and may slow down your connection. | - |
| `qrCodeMineTitle` | My QR code | AuthAnotherClient |
| `qrCodeNoGroupQrCode` | No group QR code yet | NewGroup / GroupMembers / Groups; AuthAnotherClient |
| `qrCodeScanToAddFriend` | Scan the QR code above to add me as a friend | AuthAnotherClient |
| `richTextComposerAddColumn` | Add column | - |
| `richTextComposerAddRow` | Add row | - |
| `richTextComposerContentPlaceholder` | Enter rich text | - |
| `richTextComposerFormatBoldMark` | B | - |
| `richTextComposerFormatItalicMark` | I | - |
| `richTextComposerFormatStrikethroughMark` | S | SecretChatTimerSeconds; CalendarWeekNameShortSaturday; CalendarWeekNameShortSunday |
| `richTextComposerFormatUnderlineMark` | U | - |
| `richTextComposerRemoveColumn` | Remove column | Delete / Remove |
| `richTextComposerRemoveRow` | Remove row | Delete / Remove |
| `richTextComposerRemoveTable` | Remove table | Delete / Remove |
| `settingsAboutMithka` | About Mithka | - |
| `sharedMediaCacheDeleted` | Local cache deleted | ClearCache / StorageUsage |
| `sharedMediaDownloadedSize` | Downloaded {value1} | Download / Downloaded |
| `sharedMediaDownloadProgress` | Downloaded {value1} of {value2} | Download / Downloaded |
| `sharedMediaFromSource` | From {value1} | - |
| `sharedMediaNotDownloadedSize` | Not downloaded · {value1} | Download / Downloaded |
| `stickerSetDetailAddSuccess` | Sticker added | AttachSticker / ViewPackPreview |
| `stickerSetDetailRemoved` | Sticker removed | AttachSticker / ViewPackPreview |
| `stickerSetDetailTitle` | Sticker Details | AttachSticker / ViewPackPreview |
| `tabFriendMoments` | Friends' Moments | - |
| `tabMoments` | Moments | - |
| `tdMessageBoostedGroup` | Boosted this group | Message / SendMessage / SearchMessages; NewGroup / GroupMembers / Groups |
| `tdMessageLastSeenMonthDay` | Last seen {value1}/{value2} | Message / SendMessage / SearchMessages |
| `tdMessageLastSeenTodayTime` | Last seen today at {value1}:{value2} | Message / SendMessage / SearchMessages |
| `tdMessageLastSeenYearMonthDay` | Last seen {value1}/{value2}/{value3} | Message / SendMessage / SearchMessages |
| `tdMessageLastSeenYesterdayTime` | Last seen yesterday at {value1}:{value2} | Message / SendMessage / SearchMessages |
| `tdMessagePaidMessagePriceChanged` | Message price changed to {value1} Stars | Message / SendMessage / SearchMessages |
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
| `topicChatComposerPlaceholder` | Share a thought, caption, or link | SearchAllChatsShort / SelectChat; Topics / NoTopics / CreateTopicsPermission; SharedLinksTab / ShareLink; AddCaption |
| `topicChatGroupChatTitle` | Topic Group Chat | SearchAllChatsShort / SelectChat; NewGroup / GroupMembers / Groups; Topics / NoTopics / CreateTopicsPermission |
| `topicChatLeaveChannelConfirm` | Leaving "{value1}" will delete this topic channel. Continue? | Delete / DeleteChat / DeleteAll / DeleteAllFrom; SearchAllChatsShort / SelectChat; Channel / ChannelSettings / ChannelMembers; Topics / NoTopics / CreateTopicsPermission; LeaveMegaMenu / LeaveChannel |
| `topicChatLikeCommentSummary` | {value1} likes · {value2} comments | CommentsNoNumber / RepliesTitle; SearchAllChatsShort / SelectChat; Topics / NoTopics / CreateTopicsPermission |
| `topicChatMostRelevant` | Most Relevant | SearchAllChatsShort / SelectChat; Topics / NoTopics / CreateTopicsPermission |
| `topicChatMuteMessagesToggle` | Mute Messages | Message / SendMessage / SearchMessages; SearchAllChatsShort / SelectChat; Topics / NoTopics / CreateTopicsPermission; VoipMute / ChatsUnmute |
| `topicChatNoMoreContent` | No more content | SearchAllChatsShort / SelectChat; Topics / NoTopics / CreateTopicsPermission |
| `topicChatPinnedPrefix` | Pinned \|  | PinnedMessages / PinMessage; SearchAllChatsShort / SelectChat; Topics / NoTopics / CreateTopicsPermission |
| `translationInternalNoExternalApi` | Internal translation does not use an external API | - |
| `translationLibreTranslateNoResult` | LibreTranslate returned no translation | TranslateMessage |
| `translationLibreTranslateUrlRequired` | Set the LibreTranslate URL first | TranslateMessage |
| `translationLingvaNoResult` | Lingva returned no translation | - |
| `translationMlKitLocal` | ML Kit (local) | - |
| `translationMyMemoryNoResult` | MyMemory returned no translation | - |
| `translationNativeCancelledOrTimedOut` | Native translation was canceled or timed out | - |
| `translationNativeNoExternalApi` | Native translation does not use an external API | - |
| `translationNativeNoResult` | Native translation returned no translation | - |
| `translationServiceInvalidResponse` | Invalid response format from translation service | - |
| `translationServiceReturnedStatus` | Translation service returned {value1} | - |
| `translationServiceUrlInvalid` | Invalid translation service URL | - |
| `translationSettingsService` | Translation Service | - |
| `translationSettingsTargetLanguage` | Target Language | SettingsLanguage |
| `translationSystem` | System Translation | - |
| `translationTelegram` | Telegram Translation | - |
| `updateNewVersionFound` | New Version Available | - |
| `videoPlayerForwardUnsupported` | This video cannot be forwarded | Forward / ForwardTo; AttachVideo / Videos |
| `videoPlayerPictureInPicture` | Picture in Picture | AttachVideo / Videos |
| `videoPlayerSplitScreen` | Split Screen | AttachVideo / Videos |
| `videoPlayerStreamingWhileDownloading` | Streaming while downloading | AttachVideo / Videos |
| `videoPlayerToggleDisplayMode` | Switch display mode | AttachVideo / Videos |
| `vipBadgeLabel` | VIP | - |
