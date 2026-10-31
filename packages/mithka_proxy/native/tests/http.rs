use std::io;

use leaf::{
    proxy::{http::inbound::StreamHandler, InboundStreamHandler, InboundTransport},
    session::Session,
};
use tokio::io::{duplex, AsyncReadExt, AsyncWriteExt};

#[tokio::test]
async fn absolute_requests_keep_one_header_boundary_and_the_body() {
    let (client, mut peer) = duplex(8192);
    peer.write_all(b"POST http://example.com/path?a=1 HTTP/1.1\r\nHost: example.com\r\nContent-Length: 4\r\n\r\nbody").await.unwrap();
    let InboundTransport::Stream(mut stream, session) = StreamHandler
        .handle(Session::default(), Box::new(client))
        .await
        .unwrap()
    else {
        panic!("expected TCP")
    };
    assert_eq!(session.destination.host(), "example.com");
    let mut received = vec![0; 4096];
    let n = stream.read(&mut received).await.unwrap();
    let text = std::str::from_utf8(&received[..n]).unwrap();
    assert!(text.starts_with("POST /path?a=1 HTTP/1.1\r\n"));
    assert!(text.ends_with("\r\n\r\nbody"));
    assert!(!text.contains("\r\n\r\n\r\n"));
}

#[tokio::test]
async fn an_incomplete_request_returns_eof_instead_of_spinning() {
    let (client, mut peer) = duplex(8192);
    peer.write_all(b"GET http://example.com/ HTTP/1.1\r\n")
        .await
        .unwrap();
    drop(peer);
    let result = StreamHandler
        .handle(Session::default(), Box::new(client))
        .await;
    assert!(matches!(result, Err(e) if e.kind() == io::ErrorKind::UnexpectedEof));
}

#[tokio::test]
async fn connect_preserves_pipelined_tunnel_bytes() {
    let (client, mut peer) = duplex(8192);
    peer.write_all(b"CONNECT example.com:443 HTTP/1.1\r\n\r\nfirst TLS bytes")
        .await
        .unwrap();
    let InboundTransport::Stream(mut stream, _) = StreamHandler
        .handle(Session::default(), Box::new(client))
        .await
        .unwrap()
    else {
        panic!("expected TCP")
    };
    let mut payload = [0; 15];
    stream.read_exact(&mut payload).await.unwrap();
    assert_eq!(&payload, b"first TLS bytes");
    let mut response = [0; 39];
    peer.read_exact(&mut response).await.unwrap();
    assert_eq!(&response, b"HTTP/1.1 200 Connection established\r\n\r\n");
}

#[tokio::test]
async fn headers_are_bounded() {
    let (client, mut peer) = duplex(128 * 1024);
    peer.write_all(&vec![b'x'; 65 * 1024]).await.unwrap();
    let result = StreamHandler
        .handle(Session::default(), Box::new(client))
        .await;
    assert!(result.is_err());
}
