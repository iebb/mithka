//! VLESS and Vision framing against hand-built server bytes. The optional
//! ../tool/interop.py also exercises live handshakes with a reference server.
use std::{
    io,
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc,
    },
};

use leaf::proxy::vless::{
    stream::build_vless_tcp_header_with_flow, tls::RecordStream, VlessStream,
};
use tokio::io::{duplex, AsyncRead, AsyncReadExt, AsyncWriteExt, DuplexStream};

const UUID: [u8; 16] = *b"0123456789abcdef";

fn run<F: std::future::Future>(future: F) -> F::Output {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(future)
}

fn block(command: u8, content: &[u8], padding: usize) -> Vec<u8> {
    let mut out = vec![command];
    out.extend_from_slice(&(content.len() as u16).to_be_bytes());
    out.extend_from_slice(&(padding as u16).to_be_bytes());
    out.extend_from_slice(content);
    out.extend(std::iter::repeat_n(0xee, padding));
    out
}

async fn read_all(stream: &mut (impl AsyncRead + Unpin)) -> io::Result<Vec<u8>> {
    let mut out = Vec::new();
    stream.read_to_end(&mut out).await?;
    Ok(out)
}

async fn downlink(vision: bool, bytes: Vec<u8>) -> (io::Result<Vec<u8>>, bool) {
    let (client, mut server) = duplex(1 << 16);
    let raw = Arc::new(AtomicBool::new(false));
    let mut stream = VlessStream::client(client, UUID, vision, raw.clone());
    server.write_all(&bytes).await.unwrap();
    drop(server);
    (read_all(&mut stream).await, raw.load(Ordering::Acquire))
}

#[test]
fn the_header_announces_vision_only_when_requested() {
    let plain = build_vless_tcp_header_with_flow(&UUID, "example.com", 443, 2, false);
    assert_eq!(plain[0], 0);
    assert_eq!(&plain[1..17], &UUID);
    assert_eq!(&plain[17..22], &[0, 1, 1, 187, 2]);
    assert_eq!(&plain[22..], b"\x0bexample.com");

    let vision = build_vless_tcp_header_with_flow(&UUID, "1.2.3.4", 80, 1, true);
    assert_eq!(&vision[17..36], b"\x12\x0a\x10xtls-rprx-vision");
    assert_eq!(&vision[36..], &[1, 0, 80, 1, 1, 2, 3, 4]);
}

#[test]
fn plain_vless_strips_only_the_response_prefix() {
    run(async {
        let (data, raw) = downlink(false, [&[0u8, 2, 7, 7][..], b"payload"].concat()).await;
        assert_eq!(data.unwrap(), b"payload");
        assert!(!raw);
    });
}

#[test]
fn vision_padding_is_removed_and_the_uuid_appears_once() {
    run(async {
        let mut bytes = vec![0, 0];
        bytes.extend_from_slice(&UUID);
        bytes.extend(block(0, b"ab", 3));
        bytes.extend(block(0, b"", 9));
        bytes.extend(block(1, b"cd", 0));
        bytes.extend_from_slice(b"ef");
        let (data, raw) = downlink(true, bytes).await;
        assert_eq!(data.unwrap(), b"abcdef");
        assert!(!raw);
    });
}

#[test]
fn a_direct_command_switches_reads_to_the_raw_transport() {
    run(async {
        let mut bytes = vec![0, 0];
        bytes.extend_from_slice(&UUID);
        bytes.extend(block(2, b"tls", 4));
        let (data, raw) = downlink(true, bytes).await;
        assert_eq!(data.unwrap(), b"tls");
        assert!(raw);
    });
}

#[test]
fn malformed_vision_frames_fail_instead_of_leaking_padding() {
    run(async {
        let mut wrong_uuid = vec![0, 0];
        wrong_uuid.extend_from_slice(b"fedcba9876543210");
        wrong_uuid.extend(block(1, b"x", 0));
        assert_eq!(
            downlink(true, wrong_uuid).await.0.unwrap_err().kind(),
            io::ErrorKind::InvalidData
        );

        let mut bad_command = vec![0, 0];
        bad_command.extend_from_slice(&UUID);
        bad_command.extend(block(3, b"x", 0));
        assert_eq!(
            downlink(true, bad_command).await.0.unwrap_err().kind(),
            io::ErrorKind::InvalidData
        );

        let mut truncated = vec![0, 0];
        truncated.extend_from_slice(&UUID);
        let mut padded = block(0, b"x", 8);
        padded.truncate(padded.len() - 3);
        truncated.extend(padded);
        assert_eq!(
            downlink(true, truncated).await.0.unwrap_err().kind(),
            io::ErrorKind::UnexpectedEof
        );

        assert_eq!(
            downlink(false, vec![1, 0]).await.0.unwrap_err().kind(),
            io::ErrorKind::InvalidData
        );
        assert_eq!(
            downlink(false, vec![0]).await.0.unwrap_err().kind(),
            io::ErrorKind::UnexpectedEof
        );
    });
}

#[test]
fn vision_frames_only_the_first_uplink_write() {
    run(async {
        let (client, mut server) = duplex(1 << 16);
        let mut stream = VlessStream::client(client, UUID, true, Arc::new(AtomicBool::new(false)));
        stream.write_all(b"hello").await.unwrap();
        stream.write_all(b"again").await.unwrap();
        drop(stream);
        let sent = read_all(&mut server).await.unwrap();
        assert_eq!(sent, [&UUID[..], &block(1, b"hello", 0), b"again"].concat());
    });
}

#[test]
fn plain_vless_uplink_is_unframed() {
    run(async {
        let (client, mut server) = duplex(1 << 16);
        let mut stream = VlessStream::client(client, UUID, false, Arc::new(AtomicBool::new(false)));
        stream.write_all(b"hello").await.unwrap();
        drop(stream);
        assert_eq!(read_all(&mut server).await.unwrap(), b"hello");
    });
}

#[test]
fn record_reads_never_cross_a_tls_record_boundary() {
    run(async {
        let (client, mut server): (DuplexStream, DuplexStream) = duplex(1 << 16);
        let mut records = RecordStream::new(client);
        server
            .write_all(&[
                0x17, 3, 3, 0, 2, b'a', b'b', 0x17, 3, 3, 0, 1, b'c', b'r', b'a', b'w',
            ])
            .await
            .unwrap();
        let mut sizes = Vec::new();
        let mut buf = [0u8; 64];
        for _ in 0..4 {
            sizes.push(records.read(&mut buf).await.unwrap());
        }
        // Header, body, header, body: the raw bytes after the second record
        // are still unread on the transport.
        assert_eq!(sizes, [5, 2, 5, 1]);
    });
}
