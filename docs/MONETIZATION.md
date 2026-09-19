# Nine monetization

Nine v1 uses **rewarded ads only**. The player chooses to watch an ad in exchange for one contextual puzzle hint. Core gameplay, progression, daily play and completion never depend on an ad being available.

## Architecture

```text
Nine gameplay
   |
   v
NineRewardedHintService
   |
   v
GameTimeCommerce.RewardedAdCoordinator
   |
   +-- RewardedAdProviding -> NineAdMobRewardedProvider -> Google Mobile Ads
   |
   +-- RewardReceiptPersisting -> NineRewardReceiptStore
```

Google SDK types stay inside `NineCommerce.swift`; puzzle rules and the level engine do not import Google Mobile Ads.

`RewardRequest.id` is deterministic for a single reward opportunity. GameTimeCommerce serializes attempts and stores a receipt before the reward is considered complete, so repeated callbacks cannot grant the same logical reward twice.

## Development inventory

Debug builds use Google's official iOS test inventory:

- sample app ID: `ca-app-pub-3940256099942544~1458002511`
- rewarded test unit: `ca-app-pub-3940256099942544/1712485313`

Do not replace these with live inventory for local development or automated QA.

## Product policy

- never show an ad in the five-level tutorial
- no interstitial, banner or app-open ads in v1
- no ad is inserted during active puzzle interaction
- rewarded hints are explicitly optional
- ad load, presentation or callback failure returns control to the game and never blocks play
- no coin economy is introduced just to create ad demand
- `Remove Ads` is intentionally omitted while the only placement is voluntary rewarded inventory

## Production gate — required before App Store submission

The engineering integration can ship to TestFlight with test inventory, but a release candidate must not be submitted until all of the following are complete:

1. Create the Knowlly Games / Nine app in AdMob.
2. Replace the sample `GADApplicationIdentifier` with the real app ID.
3. Add a production `NineRewardedAdUnitID` build setting / Info.plist value.
4. Add Google's current complete `SKAdNetworkItems` list from the official iOS quick-start documentation.
5. Implement and verify the required Google User Messaging Platform consent flow for regions where consent is required before personalized advertising.
6. Review ATT usage. Nine must not make gameplay depend on tracking permission.
7. Review the Google Mobile Ads SDK privacy manifest and update App Store Connect privacy/data-use disclosures to match the actual production configuration.
8. Verify rewarded ads on a signed physical-device build using test mode before enabling production inventory.
9. Confirm analytics emits `reward_offer_shown`, `reward_offer_accepted`, and `reward_completed` without personal identifiers or board coordinates.
10. Add a release check that rejects Google's sample app/ad IDs in a production archive.

If these gates are not complete, rewarded ads remain disabled in Release rather than falling back to Google's test inventory.

## SDK version policy

The Xcode project consumes Google's official Swift Package Manager repository and currently starts from Google Mobile Ads SDK `13.10.0` using an Up to Next Major Version rule. Upgrade deliberately and rerun privacy/QA checks before each App Store release.
