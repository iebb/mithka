import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../pro/mithka_pro_service.dart';

/// Motif/background are identity metadata, never instructions to paint a tile.
enum AppIconFreeMotif { penguin, pixelPenguin, letterM }

/// Native backing metadata only. Picker foregrounds remain background-free.
enum AppIconFreeBackground { neutral, telegramBlue, pinkPurple }

enum AppIconVariant {
  defaultIcon(
    key: 'default',
    labelKey: AppStringKeys.appIconDefault,
    asset: 'assets/app_icons/default.png',
    pickerAsset: 'assets/app_icons/picker/free-penguin-original.png',
    freeMotif: AppIconFreeMotif.penguin,
    background: AppIconFreeBackground.pinkPurple,
    colors: [Color(0xFFFF8F6E), Color(0xFF7C76F7)],
  ),
  white(
    key: 'white',
    labelKey: AppStringKeys.appIconWhite,
    asset: 'assets/app_icons/white.png',
    pickerAsset: 'assets/app_icons/picker/free-penguin-original.png',
    darkAsset: 'assets/app_icons/white_dark.png',
    freeMotif: AppIconFreeMotif.penguin,
    background: AppIconFreeBackground.neutral,
    colors: [Color(0xFFFFFFFF), Color(0xFFEAF2FF)],
  ),
  blue(
    key: 'blue',
    labelKey: AppStringKeys.appIconBlueGradient,
    asset: 'assets/app_icons/blue.png',
    pickerAsset: 'assets/app_icons/picker/free-penguin-original.png',
    freeMotif: AppIconFreeMotif.penguin,
    background: AppIconFreeBackground.telegramBlue,
    colors: [Color(0xFF1DB5FF), Color(0xFF224BFF)],
  ),
  purple(
    key: 'purple',
    labelKey: AppStringKeys.appIconPurpleGradient,
    asset: 'assets/app_icons/purple.png',
    pickerAsset: 'assets/app_icons/picker/legacy-purple.png',
    visibleInPicker: false,
    colors: [Color(0xFFF76AFF), Color(0xFF4D31C9)],
  ),
  pixel(
    key: 'pixel',
    labelKey: AppStringKeys.appIconPixel,
    asset: 'assets/app_icons/pixel.png',
    pickerAsset: 'assets/app_icons/picker/free-pixel.png',
    freeMotif: AppIconFreeMotif.pixelPenguin,
    background: AppIconFreeBackground.telegramBlue,
    colors: [Color(0xFF1A2034), Color(0xFF11B0D4)],
  ),
  aurora(
    key: 'aurora',
    labelKey: AppStringKeys.appIconAurora,
    asset: 'assets/app_icons/aurora.png',
    pickerAsset: 'assets/app_icons/picker/free-letter-m.png',
    freeMotif: AppIconFreeMotif.letterM,
    background: AppIconFreeBackground.telegramBlue,
    penguinCount: 0,
    colors: [Color(0xFF071F42), Color(0xFF13B6C7)],
  ),
  prism(
    key: 'prism',
    labelKey: AppStringKeys.appIconPrism,
    asset: 'assets/app_icons/prism.png',
    pickerAsset: 'assets/app_icons/picker/legacy-prism.png',
    penguinCount: 0,
    visibleInPicker: false,
    colors: [Color(0xFF352873), Color(0xFFFF76CE)],
  ),
  signal(
    key: 'signal',
    labelKey: AppStringKeys.appIconSignal,
    asset: 'assets/app_icons/signal.png',
    pickerAsset: 'assets/app_icons/picker/legacy-signal.png',
    penguinCount: 0,
    visibleInPicker: false,
    colors: [Color(0xFFFF4F65), Color(0xFF7B183C)],
  ),
  pilot(
    key: 'pilot',
    labelKey: AppStringKeys.appIconPilot,
    asset: 'assets/app_icons/pilot.png',
    pickerAsset: 'assets/app_icons/picker/01-pilot.png',
    darkAsset: 'assets/app_icons/pilot_dark.png',
    requiresSupporter: true,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  ),
  headphones(
    key: 'headphones',
    labelKey: AppStringKeys.appIconHeadphones,
    asset: 'assets/app_icons/headphones.png',
    pickerAsset: 'assets/app_icons/picker/02-headphones.png',
    darkAsset: 'assets/app_icons/headphones_dark.png',
    requiresSupporter: true,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  ),
  winter(
    key: 'winter',
    labelKey: AppStringKeys.appIconWinter,
    asset: 'assets/app_icons/winter.png',
    pickerAsset: 'assets/app_icons/picker/03-winter.png',
    darkAsset: 'assets/app_icons/winter_dark.png',
    requiresSupporter: true,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  ),
  astronaut(
    key: 'astronaut',
    labelKey: AppStringKeys.appIconAstronaut,
    asset: 'assets/app_icons/astronaut.png',
    pickerAsset: 'assets/app_icons/picker/04-astronaut.png',
    darkAsset: 'assets/app_icons/astronaut_dark.png',
    requiresSupporter: true,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  ),
  crown(
    key: 'crown',
    labelKey: AppStringKeys.appIconCrown,
    asset: 'assets/app_icons/crown.png',
    pickerAsset: 'assets/app_icons/picker/05-crown.png',
    darkAsset: 'assets/app_icons/crown_dark.png',
    requiresSupporter: true,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  ),
  party(
    key: 'party',
    labelKey: AppStringKeys.appIconParty,
    asset: 'assets/app_icons/party.png',
    pickerAsset: 'assets/app_icons/picker/06-party.png',
    darkAsset: 'assets/app_icons/party_dark.png',
    requiresSupporter: true,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  ),
  sleepy(
    key: 'sleepy',
    labelKey: AppStringKeys.appIconSleepy,
    asset: 'assets/app_icons/sleepy.png',
    pickerAsset: 'assets/app_icons/picker/07-sleepy.png',
    darkAsset: 'assets/app_icons/sleepy_dark.png',
    requiresSupporter: true,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  ),
  heart(
    key: 'heart',
    labelKey: AppStringKeys.appIconHeart,
    asset: 'assets/app_icons/heart.png',
    pickerAsset: 'assets/app_icons/picker/08-heart.png',
    darkAsset: 'assets/app_icons/heart_dark.png',
    requiresSupporter: true,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  ),
  coffee(
    key: 'coffee',
    labelKey: AppStringKeys.appIconCoffee,
    asset: 'assets/app_icons/coffee.png',
    pickerAsset: 'assets/app_icons/picker/09-coffee.png',
    darkAsset: 'assets/app_icons/coffee_dark.png',
    requiresSupporter: true,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  ),
  detective(
    key: 'detective',
    labelKey: AppStringKeys.appIconDetective,
    asset: 'assets/app_icons/detective.png',
    pickerAsset: 'assets/app_icons/picker/10-detective.png',
    darkAsset: 'assets/app_icons/detective_dark.png',
    requiresSupporter: true,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  ),
  gamer(
    key: 'gamer',
    labelKey: AppStringKeys.appIconGamer,
    asset: 'assets/app_icons/gamer.png',
    pickerAsset: 'assets/app_icons/picker/11-gamer.png',
    darkAsset: 'assets/app_icons/gamer_dark.png',
    requiresSupporter: true,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  ),
  fishing(
    key: 'fishing',
    labelKey: AppStringKeys.appIconFishing,
    asset: 'assets/app_icons/fishing.png',
    pickerAsset: 'assets/app_icons/picker/12-fishing.png',
    darkAsset: 'assets/app_icons/fishing_dark.png',
    requiresSupporter: true,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  ),
  pixelNeutral(
    key: 'pixel_neutral',
    labelKey: AppStringKeys.appIconBackgroundNeutral,
    asset: 'assets/app_icons/pixel_neutral.png',
    darkAsset: 'assets/app_icons/pixel_neutral_dark.png',
    pickerAsset: 'assets/app_icons/picker/free-pixel.png',
    freeMotif: AppIconFreeMotif.pixelPenguin,
    background: AppIconFreeBackground.neutral,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  ),
  pixelGradient(
    key: 'pixel_gradient',
    labelKey: AppStringKeys.appIconBackgroundPinkPurple,
    asset: 'assets/app_icons/pixel_gradient.png',
    darkAsset: 'assets/app_icons/pixel_gradient_dark.png',
    pickerAsset: 'assets/app_icons/picker/free-pixel.png',
    freeMotif: AppIconFreeMotif.pixelPenguin,
    background: AppIconFreeBackground.pinkPurple,
    colors: [Color(0xFFFF8F6E), Color(0xFF7C76F7)],
  ),
  letterMNeutral(
    key: 'letter_m_neutral',
    labelKey: AppStringKeys.appIconBackgroundNeutral,
    asset: 'assets/app_icons/letter_m_neutral.png',
    darkAsset: 'assets/app_icons/letter_m_neutral_dark.png',
    pickerAsset: 'assets/app_icons/picker/free-letter-m.png',
    freeMotif: AppIconFreeMotif.letterM,
    background: AppIconFreeBackground.neutral,
    penguinCount: 0,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  ),
  letterMGradient(
    key: 'letter_m_gradient',
    labelKey: AppStringKeys.appIconBackgroundPinkPurple,
    asset: 'assets/app_icons/letter_m_gradient.png',
    darkAsset: 'assets/app_icons/letter_m_gradient_dark.png',
    pickerAsset: 'assets/app_icons/picker/free-letter-m.png',
    freeMotif: AppIconFreeMotif.letterM,
    background: AppIconFreeBackground.pinkPurple,
    penguinCount: 0,
    colors: [Color(0xFFFF8F6E), Color(0xFF7C76F7)],
  ),
  skateboard(
    key: 'skateboard',
    labelKey: AppStringKeys.appIconSkateboard,
    asset: 'assets/app_icons/skateboard.png',
    darkAsset: 'assets/app_icons/skateboard_dark.png',
    pickerAsset: 'assets/app_icons/picker/13-skateboard.png',
    requiresSupporter: true,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  ),
  surfboard(
    key: 'surfboard',
    labelKey: AppStringKeys.appIconSurfboard,
    asset: 'assets/app_icons/surfboard.png',
    darkAsset: 'assets/app_icons/surfboard_dark.png',
    pickerAsset: 'assets/app_icons/picker/14-surfboard.png',
    requiresSupporter: true,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  ),
  basketball(
    key: 'basketball',
    labelKey: AppStringKeys.appIconBasketball,
    asset: 'assets/app_icons/basketball.png',
    darkAsset: 'assets/app_icons/basketball_dark.png',
    pickerAsset: 'assets/app_icons/picker/15-basketball.png',
    requiresSupporter: true,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  ),
  football(
    key: 'football',
    labelKey: AppStringKeys.appIconFootball,
    asset: 'assets/app_icons/football.png',
    darkAsset: 'assets/app_icons/football_dark.png',
    pickerAsset: 'assets/app_icons/picker/16-football.png',
    requiresSupporter: true,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  ),
  tennis(
    key: 'tennis',
    labelKey: AppStringKeys.appIconTennis,
    asset: 'assets/app_icons/tennis.png',
    darkAsset: 'assets/app_icons/tennis_dark.png',
    pickerAsset: 'assets/app_icons/picker/17-tennis.png',
    requiresSupporter: true,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  ),
  skiing(
    key: 'skiing',
    labelKey: AppStringKeys.appIconSkiing,
    asset: 'assets/app_icons/skiing.png',
    darkAsset: 'assets/app_icons/skiing_dark.png',
    pickerAsset: 'assets/app_icons/picker/18-skiing.png',
    requiresSupporter: true,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  ),
  painter(
    key: 'painter',
    labelKey: AppStringKeys.appIconPainter,
    asset: 'assets/app_icons/painter.png',
    darkAsset: 'assets/app_icons/painter_dark.png',
    pickerAsset: 'assets/app_icons/picker/19-painter.png',
    requiresSupporter: true,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  ),
  guitar(
    key: 'guitar',
    labelKey: AppStringKeys.appIconGuitar,
    asset: 'assets/app_icons/guitar.png',
    darkAsset: 'assets/app_icons/guitar_dark.png',
    pickerAsset: 'assets/app_icons/picker/20-guitar.png',
    requiresSupporter: true,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  ),
  drummer(
    key: 'drummer',
    labelKey: AppStringKeys.appIconDrummer,
    asset: 'assets/app_icons/drummer.png',
    darkAsset: 'assets/app_icons/drummer_dark.png',
    pickerAsset: 'assets/app_icons/picker/21-drummer.png',
    requiresSupporter: true,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  ),
  photographer(
    key: 'photographer',
    labelKey: AppStringKeys.appIconPhotographer,
    asset: 'assets/app_icons/photographer.png',
    darkAsset: 'assets/app_icons/photographer_dark.png',
    pickerAsset: 'assets/app_icons/picker/22-photographer.png',
    requiresSupporter: true,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  ),
  magician(
    key: 'magician',
    labelKey: AppStringKeys.appIconMagician,
    asset: 'assets/app_icons/magician.png',
    darkAsset: 'assets/app_icons/magician_dark.png',
    pickerAsset: 'assets/app_icons/picker/23-magician.png',
    requiresSupporter: true,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  ),
  chef(
    key: 'chef',
    labelKey: AppStringKeys.appIconChef,
    asset: 'assets/app_icons/chef.png',
    darkAsset: 'assets/app_icons/chef_dark.png',
    pickerAsset: 'assets/app_icons/picker/24-chef.png',
    requiresSupporter: true,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  ),
  reader(
    key: 'reader',
    labelKey: AppStringKeys.appIconReader,
    asset: 'assets/app_icons/reader.png',
    darkAsset: 'assets/app_icons/reader_dark.png',
    pickerAsset: 'assets/app_icons/picker/25-reader.png',
    requiresSupporter: true,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  ),
  scientist(
    key: 'scientist',
    labelKey: AppStringKeys.appIconScientist,
    asset: 'assets/app_icons/scientist.png',
    darkAsset: 'assets/app_icons/scientist_dark.png',
    pickerAsset: 'assets/app_icons/picker/26-scientist.png',
    requiresSupporter: true,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  ),
  gardener(
    key: 'gardener',
    labelKey: AppStringKeys.appIconGardener,
    asset: 'assets/app_icons/gardener.png',
    darkAsset: 'assets/app_icons/gardener_dark.png',
    pickerAsset: 'assets/app_icons/picker/27-gardener.png',
    requiresSupporter: true,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  ),
  mailCarrier(
    key: 'mail-carrier',
    labelKey: AppStringKeys.appIconMailCarrier,
    asset: 'assets/app_icons/mail-carrier.png',
    darkAsset: 'assets/app_icons/mail-carrier_dark.png',
    pickerAsset: 'assets/app_icons/picker/28-mail-carrier.png',
    requiresSupporter: true,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  ),
  pirate(
    key: 'pirate',
    labelKey: AppStringKeys.appIconPirate,
    asset: 'assets/app_icons/pirate.png',
    darkAsset: 'assets/app_icons/pirate_dark.png',
    pickerAsset: 'assets/app_icons/picker/29-pirate.png',
    requiresSupporter: true,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  ),
  dragon(
    key: 'dragon',
    labelKey: AppStringKeys.appIconDragon,
    asset: 'assets/app_icons/dragon.png',
    darkAsset: 'assets/app_icons/dragon_dark.png',
    pickerAsset: 'assets/app_icons/picker/30-dragon.png',
    requiresSupporter: true,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  ),
  bubblegum(
    key: 'bubblegum',
    labelKey: AppStringKeys.appIconBubblegum,
    asset: 'assets/app_icons/bubblegum.png',
    darkAsset: 'assets/app_icons/bubblegum_dark.png',
    pickerAsset: 'assets/app_icons/picker/31-bubblegum.png',
    requiresSupporter: true,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  ),
  raincoat(
    key: 'raincoat',
    labelKey: AppStringKeys.appIconRaincoat,
    asset: 'assets/app_icons/raincoat.png',
    darkAsset: 'assets/app_icons/raincoat_dark.png',
    pickerAsset: 'assets/app_icons/picker/32-raincoat.png',
    requiresSupporter: true,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  ),
  noodles(
    key: 'noodles',
    labelKey: AppStringKeys.appIconNoodles,
    asset: 'assets/app_icons/noodles.png',
    darkAsset: 'assets/app_icons/noodles_dark.png',
    pickerAsset: 'assets/app_icons/picker/33-noodles.png',
    requiresSupporter: true,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  ),
  iceCream(
    key: 'ice-cream',
    labelKey: AppStringKeys.appIconIceCream,
    asset: 'assets/app_icons/ice-cream.png',
    darkAsset: 'assets/app_icons/ice-cream_dark.png',
    pickerAsset: 'assets/app_icons/picker/34-ice-cream.png',
    requiresSupporter: true,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  ),
  sunflower(
    key: 'sunflower',
    labelKey: AppStringKeys.appIconSunflower,
    asset: 'assets/app_icons/sunflower.png',
    darkAsset: 'assets/app_icons/sunflower_dark.png',
    pickerAsset: 'assets/app_icons/picker/35-sunflower.png',
    requiresSupporter: true,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  ),
  ninja(
    key: 'ninja',
    labelKey: AppStringKeys.appIconNinja,
    asset: 'assets/app_icons/ninja.png',
    darkAsset: 'assets/app_icons/ninja_dark.png',
    pickerAsset: 'assets/app_icons/picker/36-ninja.png',
    requiresSupporter: true,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  ),
  highFive(
    key: 'high-five',
    labelKey: AppStringKeys.appIconHighFive,
    asset: 'assets/app_icons/high-five.png',
    darkAsset: 'assets/app_icons/high-five_dark.png',
    pickerAsset: 'assets/app_icons/picker/37-high-five.png',
    requiresSupporter: true,
    penguinCount: 2,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  ),
  hug(
    key: 'hug',
    labelKey: AppStringKeys.appIconHug,
    asset: 'assets/app_icons/hug.png',
    darkAsset: 'assets/app_icons/hug_dark.png',
    pickerAsset: 'assets/app_icons/picker/38-hug.png',
    requiresSupporter: true,
    penguinCount: 2,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  ),
  seesaw(
    key: 'seesaw',
    labelKey: AppStringKeys.appIconSeesaw,
    asset: 'assets/app_icons/seesaw.png',
    darkAsset: 'assets/app_icons/seesaw_dark.png',
    pickerAsset: 'assets/app_icons/picker/39-seesaw.png',
    requiresSupporter: true,
    penguinCount: 2,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  ),
  dance(
    key: 'dance',
    labelKey: AppStringKeys.appIconDance,
    asset: 'assets/app_icons/dance.png',
    darkAsset: 'assets/app_icons/dance_dark.png',
    pickerAsset: 'assets/app_icons/picker/40-dance.png',
    requiresSupporter: true,
    penguinCount: 2,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  ),
  pillowFight(
    key: 'pillow-fight',
    labelKey: AppStringKeys.appIconPillowFight,
    asset: 'assets/app_icons/pillow-fight.png',
    darkAsset: 'assets/app_icons/pillow-fight_dark.png',
    pickerAsset: 'assets/app_icons/picker/41-pillow-fight.png',
    requiresSupporter: true,
    penguinCount: 2,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  ),
  snowball(
    key: 'snowball',
    labelKey: AppStringKeys.appIconSnowball,
    asset: 'assets/app_icons/snowball.png',
    darkAsset: 'assets/app_icons/snowball_dark.png',
    pickerAsset: 'assets/app_icons/picker/42-snowball.png',
    requiresSupporter: true,
    penguinCount: 2,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  ),
  parade(
    key: 'parade',
    labelKey: AppStringKeys.appIconParade,
    asset: 'assets/app_icons/parade.png',
    darkAsset: 'assets/app_icons/parade_dark.png',
    pickerAsset: 'assets/app_icons/picker/43-parade.png',
    requiresSupporter: true,
    penguinCount: 3,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  ),
  choir(
    key: 'choir',
    labelKey: AppStringKeys.appIconChoir,
    asset: 'assets/app_icons/choir.png',
    darkAsset: 'assets/app_icons/choir_dark.png',
    pickerAsset: 'assets/app_icons/picker/44-choir.png',
    requiresSupporter: true,
    penguinCount: 3,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  ),
  stack(
    key: 'stack',
    labelKey: AppStringKeys.appIconStack,
    asset: 'assets/app_icons/stack.png',
    darkAsset: 'assets/app_icons/stack_dark.png',
    pickerAsset: 'assets/app_icons/picker/45-stack.png',
    requiresSupporter: true,
    penguinCount: 3,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  ),
  picnic(
    key: 'picnic',
    labelKey: AppStringKeys.appIconPicnic,
    asset: 'assets/app_icons/picnic.png',
    darkAsset: 'assets/app_icons/picnic_dark.png',
    pickerAsset: 'assets/app_icons/picker/46-picnic.png',
    requiresSupporter: true,
    penguinCount: 3,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  ),
  paperPlanes(
    key: 'paper-planes',
    labelKey: AppStringKeys.appIconPaperPlanes,
    asset: 'assets/app_icons/paper-planes.png',
    darkAsset: 'assets/app_icons/paper-planes_dark.png',
    pickerAsset: 'assets/app_icons/picker/47-paper-planes.png',
    requiresSupporter: true,
    penguinCount: 3,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  ),
  stargazing(
    key: 'stargazing',
    labelKey: AppStringKeys.appIconStargazing,
    asset: 'assets/app_icons/stargazing.png',
    darkAsset: 'assets/app_icons/stargazing_dark.png',
    pickerAsset: 'assets/app_icons/picker/48-stargazing.png',
    requiresSupporter: true,
    penguinCount: 3,
    colors: [Color(0xFFFFFFFF), Color(0xFF0B0B0D)],
  );

  const AppIconVariant({
    required this.key,
    required this.labelKey,
    required this.asset,
    required this.pickerAsset,
    required this.colors,
    this.requiresSupporter = false,
    this.darkAsset,
    this.visibleInPicker = true,
    this.freeMotif,
    this.background,
    this.penguinCount = 1,
  });

  final String key;
  final String labelKey;
  // Opaque native/Dock path: never repoint to transparent picker artwork.
  final String asset;
  final String pickerAsset;
  final bool visibleInPicker;
  final AppIconFreeMotif? freeMotif;
  final AppIconFreeBackground? background;
  final int penguinCount;

  String? get backgroundLabelKey => switch (background) {
    AppIconFreeBackground.neutral => AppStringKeys.appIconBackgroundNeutral,
    AppIconFreeBackground.telegramBlue =>
      AppStringKeys.appIconBackgroundTelegramBlue,
    AppIconFreeBackground.pinkPurple =>
      AppStringKeys.appIconBackgroundPinkPurple,
    null => null,
  };

  String? get motifLabelKey => switch (freeMotif) {
    AppIconFreeMotif.penguin => AppStringKeys.appIconMotifPenguin,
    AppIconFreeMotif.pixelPenguin => AppStringKeys.appIconMotifPixelPenguin,
    AppIconFreeMotif.letterM => AppStringKeys.appIconMotifLetterM,
    null => null,
  };

  /// Full accessibility names include both motif and background. Hidden legacy
  /// selections keep their actual existing localized legacy name.
  String get fullSemanticNameKey => switch (this) {
    AppIconVariant.white => AppStringKeys.appIconPenguinNeutral,
    AppIconVariant.blue => AppStringKeys.appIconPenguinTelegramBlue,
    AppIconVariant.defaultIcon => AppStringKeys.appIconPenguinPinkPurple,
    AppIconVariant.pixelNeutral => AppStringKeys.appIconPixelPenguinNeutral,
    AppIconVariant.pixel => AppStringKeys.appIconPixelPenguinTelegramBlue,
    AppIconVariant.pixelGradient => AppStringKeys.appIconPixelPenguinPinkPurple,
    AppIconVariant.letterMNeutral => AppStringKeys.appIconLetterMNeutral,
    AppIconVariant.aurora => AppStringKeys.appIconLetterMTelegramBlue,
    AppIconVariant.letterMGradient => AppStringKeys.appIconLetterMPinkPurple,
    _ => labelKey,
  };
  String? get pickerLabelKey =>
      freeMotif == null ? labelKey : backgroundLabelKey;
  bool get hasDeferredPickerCopy => pickerLabelKey == null;

  final List<Color> colors;
  final bool requiresSupporter;
  final String? darkAsset;

  String previewAsset(Brightness brightness) =>
      brightness == Brightness.dark ? darkAsset ?? asset : asset;

  /// Complete compatibility catalogue; first 20 positions remain unchanged.
  static const knownValues = values;

  /// Exact approved motif-major order, independent of compatibility enum order.
  // Visual order is not default selection. defaultIcon remains the primary
  // pink-purple Penguin for new installs and saved `default` selections.
  static const visibleFree = <AppIconVariant>[
    white,
    blue,
    defaultIcon,
    pixelNeutral,
    pixel,
    pixelGradient,
    letterMNeutral,
    aurora,
    letterMGradient,
  ];

  static List<AppIconVariant> get supporterVariants => values
      .where((variant) => variant.requiresSupporter)
      .toList(growable: false);

  static List<AppIconVariant> forPlatform(TargetPlatform platform) => [
    ...visibleFree,
    if (supporterIconsAvailableForPlatform(platform)) ...supporterVariants,
  ].toList(growable: false);

  /// Recognized-only lookup: initialization must not lose an unknown raw ID.
  static AppIconVariant? recognizedFromKey(String? key) {
    for (final variant in knownValues) {
      if (variant.key == key) return variant;
    }
    return null;
  }

  /// Legacy API fallback; not authoritative for current-selection semantics.
  static AppIconVariant fromKey(String? key) =>
      recognizedFromKey(key) ?? AppIconVariant.defaultIcon;
}

bool appIconPickerAvailableForPlatform(
  TargetPlatform platform, {
  bool isWeb = kIsWeb,
}) =>
    !isWeb &&
    switch (platform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.macOS => true,
      TargetPlatform.fuchsia ||
      TargetPlatform.linux ||
      TargetPlatform.windows => false,
    };

enum RetainedUnknownIconSource { savedPreference, nativeCurrent }

@immutable
class RetainedUnknownIconState {
  const RetainedUnknownIconState({required this.key, required this.source});

  final String key;
  final RetainedUnknownIconSource source;
  // No invented asset, label, selection claim, or interactive picker option.
}

class AppIconController extends ChangeNotifier {
  AppIconController(
    this._prefs, {
    MithkaProService? proService,
    TargetPlatform? platform,
  }) : _pro = proService ?? MithkaProService.shared,
       _platform = platform ?? defaultTargetPlatform {
    _pro.addListener(_entitlementChanged);
  }

  static const _channel = MethodChannel('mithka/app_icon');
  static const _selectedKey = 'selected_app_icon';

  final SharedPreferences _prefs;
  final MithkaProService _pro;
  final TargetPlatform _platform;
  bool _disposed = false;

  bool get supporterAvailable => supporterIconsAvailableForPlatform(_platform);
  bool get activeSupporter => _pro.isPro;
  MithkaProService get proService => _pro;
  List<AppIconVariant> get availableVariants =>
      AppIconVariant.forPlatform(_platform);
  bool isLocked(AppIconVariant icon) =>
      icon.requiresSupporter && !isCurrent(icon) && !activeSupporter;

  void _entitlementChanged() {
    if (!_disposed) notifyListeners();
  }

  AppIconVariant _variant = AppIconVariant.defaultIcon;
  bool _supported = false;
  bool _loading = false;

  /// Compatibility getter only. UI selected traits MUST use isCurrent;
  /// currentVariant is null when the bridge/preference supplies an unknown ID.
  AppIconVariant get variant => _variant;
  RetainedUnknownIconState? _retainedUnknownState;
  RetainedUnknownIconState? get retainedUnknownState => _retainedUnknownState;
  AppIconVariant? get currentVariant =>
      _retainedUnknownState == null ? _variant : null;
  String get currentKey => _retainedUnknownState?.key ?? _variant.key;
  bool isCurrent(AppIconVariant icon) => currentVariant == icon;

  /// Non-interactive Current icon status data, not an extra selectable tile.
  /// Use the existing legacy labelKey between appIconCurrentHeading and
  /// appIconCurrentNote; never expose a button/Available/unlock action here.
  AppIconVariant? get unlistedCurrent {
    final current = currentVariant;
    return current != null && !availableVariants.contains(current)
        ? current
        : null;
  }

  void _retainKey(String key, RetainedUnknownIconSource source) {
    final recognized = AppIconVariant.recognizedFromKey(key);
    if (recognized == null) {
      _retainedUnknownState = RetainedUnknownIconState(
        key: key,
        source: source,
      );
    } else {
      _variant = recognized;
      _retainedUnknownState = null;
    }
  }

  bool get supported => _supported;
  bool get loading => _loading;

  Future<void> initialize() async {
    final saved = _prefs.getString(_selectedKey);
    _retainKey(saved ?? 'default', RetainedUnknownIconSource.savedPreference);
    try {
      _supported = await _channel.invokeMethod<bool>('isSupported') ?? false;
      final current = await _channel.invokeMethod<String>('currentIcon');
      if (current != null && current.isNotEmpty) {
        // Explicit native current retains its established precedence.
        _retainKey(current, RetainedUnknownIconSource.nativeCurrent);
      }
      // Startup is read-only for known AND unknown identities. Native-current
      // precedence is in memory; only an explicit successful choice writes prefs.
    } catch (_) {
      _supported = false;
    }
    notifyListeners();
  }

  Future<bool> setVariant(AppIconVariant next) async {
    if (!_supported || _loading || _disposed) return false;
    if (next.requiresSupporter && !supporterAvailable) return false;
    // Retain an already-applied paid icon after expiry; never reset native state.
    if (isCurrent(next) && !next.requiresSupporter) return true;
    _loading = true;
    notifyListeners();
    try {
      if (next.requiresSupporter) {
        final verified = await _pro.refreshEntitlement();
        if (!verified || !_pro.isPro) return false;
      }
      if (_disposed) return false;
      if (isCurrent(next)) return true;
      await _channel.invokeMethod<void>('setIcon', {'name': next.key});
      _variant = next;
      _retainedUnknownState = null;
      return await _prefs.setString(_selectedKey, next.key);
    } catch (_) {
      // A rejected native change does not persist or optimistically select it.
      return false;
    } finally {
      _loading = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _pro.removeListener(_entitlementChanged);
    super.dispose();
  }
}
