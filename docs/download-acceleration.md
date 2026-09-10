# Download acceleration

Source review: 2026-09-09. Compared with
[`iyear/tdl` at `70c561c0`](https://github.com/iyear/tdl/tree/70c561c0a6d44d8d7fffdea14988fc4104bc56d2)
and Mithka's pinned TDLib `1.8.67`, upstream commit `d1085f9c`.

## How tdl accelerates downloads

tdl uses gotd's MTProto downloader directly. It requests 1 MiB parts in parallel,
writes each part at its file offset, and reuses a connection pool for each data
center. Its defaults allow four workers per file, two concurrent files, and a
pool of up to eight connections per data center. Small files use fewer workers.
These limits control different resources; increasing one does not guarantee a
faster transfer.

Sources:

- [Downloader and native part size](https://github.com/iyear/tdl/blob/70c561c0a6d44d8d7fffdea14988fc4104bc56d2/core/downloader/downloader.go)
- [Per-data-center connection pools](https://github.com/iyear/tdl/blob/70c561c0a6d44d8d7fffdea14988fc4104bc56d2/core/dcpool/dcpool.go)
- [Concurrency defaults](https://github.com/iyear/tdl/blob/70c561c0a6d44d8d7fffdea14988fc4104bc56d2/cmd/root.go)
- [Worker counts for small files](https://github.com/iyear/tdl/blob/70c561c0a6d44d8d7fffdea14988fc4104bc56d2/core/util/tutil/tutil.go)

## What Mithka already implements

`TransferBoostConfig` enables download boost by default with 1 MiB chunks and a
maximum of 12 pending native part requests per file. Existing preferences,
including an explicit opt-out, remain effective. TDLib retains the part size
of a resumed partial file and its own sizing for files no larger than 1 MiB.

`TdClient._start` passes these values through `td_mithka_set_transfer_boost`
before creating native clients. The pinned native patch applies them to
`FileDownloader` and raises the per-data-center download resource budget to at
least the configured chunk size multiplied by parallelism. Native scheduling,
cached-part resumption, retry handling, and file verification remain in TDLib.
The parallelism value is a ceiling, not a promise that every request is active.

TDLib also already balances requests across data-center sessions. At the pinned
upstream version it uses two download sessions normally, or eight when the
account is Premium or `session_count > 1`. Mithka preserves these transport
defaults. tdl's pool size is not the same setting as Mithka's per-file part
parallelism; increasing general-purpose sessions would also affect other traffic.

Sources:

- App configuration: `lib/settings/transfer_boost_config.dart`
- Native bridge: `lib/tdlib/td_client.dart`, `lib/tdlib/td_bindings.dart`
- Artifact pin: `scripts/tdjson-manifest.json`
- [Pinned Mithka transfer patch](https://github.com/iebb/mithka-tdjson/blob/fb217c3c586565c8bc5d3d0d6c59051046d5fbf6/patches/mithka-transfer-boost.patch)
- [TDLib session counts](https://github.com/tdlib/td/blob/d1085f9cebc5a62379991ae1652673954f229c1f/td/telegram/net/NetQueryDispatcher.cpp)
- [TDLib session balancing](https://github.com/tdlib/td/blob/d1085f9cebc5a62379991ae1652673954f229c1f/td/telegram/net/SessionMultiProxy.cpp)

## App request contract

Parallelism must happen inside the native downloader. Unlike independent MTProto
part requests, TDLib's public `downloadFile` calls share one current user-requested
offset and limit per file. A new request with different bounds cancels earlier
synchronous requests. See the [API contract](https://github.com/tdlib/td/blob/d1085f9cebc5a62379991ae1652673954f229c1f/td/generate/scheme/td_api.tl)
and [FileManager implementation](https://github.com/tdlib/td/blob/d1085f9cebc5a62379991ae1652673954f229c1f/td/telegram/files/FileManager.cpp).

`TdFileCenter` therefore follows these rules:

- Whole files start with one asynchronous request, `offset: 0`, `limit: 0`.
  `updateFile` carries subsequent progress and completion. An estimated or
  unknown size never becomes a cutoff.
- Playback prefixes use one synchronous request for the entire requested range,
  with its timeout passed to the actual TDLib query. Native transfer boost still
  parallelizes the underlying parts.
- Cancellation and errors do not start another batch of Dart workers or an
  unlimited fallback download.
- Independent file downloads remain concurrent and account-scoped.

The previous implementation split a range into concurrent public `downloadFile`
requests, causing them to cancel each other. Whole-file downloads also walked
these chunks and then restarted an unlimited download when any chunk failed,
including after user cancellation. Both paths now let the native downloader own
the transfer. The loopback video server already coordinates its bounded ranges
and remains responsible for playback buffering and seeks.

## Validation and limits

`test/priority_media_download_test.dart` models TDLib's cancellation behavior and
covers ranges, concurrent files, progress/completion, cancellation, failures,
account routing, and the query timeout. Its range regression failed against the
previous implementation and passed after removing the Dart chunk workers.

These checks establish request correctness, not a measured throughput gain.
Compare the same large file with an empty cache, the same account, network and
proxy, and the same native artifact to measure speed. Telegram's server-side
account and flood limits still apply; this change does not bypass them.
