# Capture from social media: what is legal and effortless

Research of 2026-10-18 (official docs, plus live calls to the public oEmbed endpoints). APIs and terms change often: re-check before building a slice that depends on a row here. Owner constraint: **no scraping, only legal and effortless ways.**

## What we get from a shared link

| Source | Official route | What comes back | May we store it? | Use |
| --- | --- | --- | --- | --- |
| TikTok | public oEmbed, no token | `title` = the full caption with hashtags, author, thumbnail | caption in the user’s private memory: defensible; thumbnail: link to it, don’t copy | ✅ best social source |
| YouTube / Shorts | public oEmbed, no key | title, channel, thumbnail | store the URL and video ID; treat title and thumbnail as a cache to refresh (Developer Policies, 30 days for API data) | ✅ |
| X | `publish.x.com/oembed`, no auth | author, post text inside `html` | only if kept current (delete within 24 h when deleted on X) | ⚠️ text at save time only, then the user’s own note |
| Instagram / Facebook | Meta oEmbed Read (app review, business verification) | since 2025-11 only embed `html`: no caption, author or thumbnail | **no**: “only for embedding… not extracting or persisting the metadata” | ❌ URL only |
| Pinterest | public oEmbed | title, author, thumbnail | **no**: “you may not store any information… call the API each time” | ❌ URL only (live preview at most) |
| Reddit | Data API (OAuth, approval since 2025-11) | blocked without approval | per Data API terms | ❌ URL only |
| Google Maps share links | follow the `maps.app.goo.gl` redirect once | place name and coordinates in the final URL | one user’s own link: low risk; Places API **place_id may be stored forever**, coordinates 30 days | ✅ place |
| Websites, events, recipes | one polite fetch: Open Graph + schema.org JSON-LD | title, description, image, event dates, place, price | standard link preview | ✅ |

**Consequence:** for Instagram, probably the most common source, we only ever have the link. The meaning has to come from the user: **a few words at share time**, or **a screenshot** they share (their own content, read by AI).

## How a post gets into the app

| Channel | iPhone | Android | User effort | Our effort | Cost |
| --- | --- | --- | --- | --- | --- |
| Web app share target | ❌ (Safari still can’t receive shares) | ✅ installed web app | Share → Oh, right! | small (manifest + one route) | free |
| iOS Shortcut | ✅ appears in every share sheet | – | import once, 2–3 taps per save | small (token-auth save endpoint) | free |
| Native app + share extension (Flutter, `receive_sharing_intent`) | ✅ | ✅ | install once, 2 taps | ~half a day for iOS, little on Android | Apple $99/yr (TestFlight: 100 internal testers); Play $25 + a 14-day closed test with 12 testers |
| Telegram bot | ✅ | ✅ | Share → Telegram → bot | small | free |
| WhatsApp Cloud API | ✅ | ✅ | Share → WhatsApp → chat | medium (Meta app, own number) | free within user-started chats (pricing reports conflict) |
| Email forward | ✅ | ✅ | slow (type an address) | small | free |

- Instagram and TikTok pass **mostly just the URL** to the share sheet; the caption usually doesn’t come along.
- **Screenshots:** since iOS 26 the screenshot preview has a Share button, so it goes straight to the app. Reading it: free on the phone (Apple Vision, Google ML Kit; native app only) or ~$0.0002–0.002 per image with a small cloud vision model.
- **Bulk import:** a user may upload their own *Download your information* file. Instagram’s has saved posts as URL + author + time (no caption); TikTok’s has favourites and likes as links. The EU portability APIs (TikTok, Google) need security reviews and only reach EU/UK users: too heavy for now.

## Testing

- iOS Simulator (free, with Xcode): runs a native app and its share extension; share from Safari or Photos. Instagram/TikTok can’t be installed there, so check their real share payload on a real iPhone.
- Android Emulator with a *Google Play* system image: install real Instagram/TikTok and test end to end.

## Unverified

Exact share payloads of Instagram/TikTok/YouTube on each OS (log them on real phones); whether YouTube’s 30-day rule covers oEmbed; TikTok oEmbed limits; WhatsApp service pricing after 2026-10-01; whether a free Apple account allows the App Group a share extension uses.

## Sources

- Instagram oEmbed: https://developers.facebook.com/docs/instagram-platform/oembed · fields: https://developers.facebook.com/docs/graph-api/reference/instagram-oembed · Meta oEmbed Read: https://developers.facebook.com/docs/features-reference/meta-oembed-read · deprecation: https://iframely.com/updates/193071-facebook-and-instagram-oembed-thumbnail-deprecation
- TikTok embeds: https://developers.tiktok.com/doc/embed-videos · terms: https://www.tiktok.com/legal/page/global/tik-tok-developer-terms-of-service/en · Data Portability API: https://developers.tiktok.com/products/data-portability-api/
- YouTube Developer Policies: https://developers.google.com/youtube/terms/developer-policies
- X Developer Policy: https://docs.x.com/developer-terms/policy
- Pinterest developer guidelines: https://policy.pinterest.com/en/developer-guidelines
- Reddit data access: https://support.reddithelp.com/hc/en-us/articles/14945211791892-Developer-Platform-Accessing-Reddit-Data
- Google Maps terms: https://www.google.com/help/terms_maps/ · Places policies: https://developers.google.com/maps/documentation/places/web-service/policies · goo.gl links kept: https://ppc.land/google-changes-course-on-goo-gl-shutdown-preserves-actively-used-links/ · Nominatim policy: https://operations.osmfoundation.org/policies/nominatim/
- Google Data Portability API: https://developers.google.com/data-portability/user-guide/overview
- Web Share Target: https://developer.chrome.com/docs/capabilities/web-apis/web-share-target · iOS web app limits: https://tappwa.com/blog/ios-pwa-limitations-2026
- Flutter: https://pub.dev/packages/receive_sharing_intent · https://docs.flutter.dev/platform-integration/ios/app-extensions
- Apple Developer Program: https://developer.apple.com/programs/
- Share sheet payload reports: https://forum.obsidian.md/t/ios-share-sheet-full-text-capture-fails-or-produces-unusable-titles-for-facebook-and-instagram/117939 · https://github.com/danielgentile22/WeCooked/issues/39
- iOS Shortcuts calling APIs: https://stevedylan.dev/posts/api-calls-in-ios-shortcuts/
- Telegram bot pricing: https://aziqdev.com/blog/telegram-bot-api-pricing · WhatsApp pricing: https://developers.facebook.com/docs/whatsapp/pricing
- Vision costs: https://platform.claude.com/docs/en/build-with-claude/vision · https://ai.google.dev/gemini-api/docs/pricing
- iOS 26 screenshots: https://www.tomsguide.com/phones/iphones/apple-switched-up-screenshots-in-ios-26-heres-how-to-get-the-old-version-back
