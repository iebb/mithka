//! Preserve TLS record boundaries so a Vision direct-copy transition cannot
//! read encrypted and raw bytes together into rustls.
use std::{
    io::{self, Read},
    pin::Pin,
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc,
    },
    task::{Context, Poll},
};
use tokio::io::{AsyncBufRead, AsyncRead, AsyncWrite, ReadBuf};
use tokio_rustls::client::TlsStream;

pub struct RecordStream<S> {
    inner: S,
    header: [u8; 5],
    header_len: usize,
    remaining: usize,
}
impl<S> RecordStream<S> {
    pub fn new(inner: S) -> Self {
        Self {
            inner,
            header: [0; 5],
            header_len: 0,
            remaining: 0,
        }
    }
}
impl<S: AsyncRead + Unpin> AsyncRead for RecordStream<S> {
    fn poll_read(
        self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &mut ReadBuf<'_>,
    ) -> Poll<io::Result<()>> {
        let this = self.get_mut();
        let count = buf.remaining().min(if this.remaining > 0 {
            this.remaining
        } else {
            5 - this.header_len
        });
        if count == 0 {
            return Poll::Ready(Ok(()));
        }
        let mut limited = ReadBuf::new(buf.initialize_unfilled_to(count));
        match Pin::new(&mut this.inner).poll_read(cx, &mut limited) {
            Poll::Ready(Ok(())) => {
                let n = limited.filled().len();
                if this.remaining > 0 {
                    this.remaining -= n;
                } else {
                    this.header[this.header_len..this.header_len + n]
                        .copy_from_slice(limited.filled());
                    this.header_len += n;
                    if this.header_len == 5 {
                        this.remaining =
                            u16::from_be_bytes([this.header[3], this.header[4]]) as usize;
                        if this.remaining > 18432 {
                            return Poll::Ready(Err(io::Error::new(
                                io::ErrorKind::InvalidData,
                                "invalid TLS record",
                            )));
                        }
                        this.header_len = 0;
                    }
                }
                buf.advance(n);
                Poll::Ready(Ok(()))
            }
            result => result,
        }
    }
}
impl<S: AsyncWrite + Unpin> AsyncWrite for RecordStream<S> {
    fn poll_write(self: Pin<&mut Self>, cx: &mut Context<'_>, b: &[u8]) -> Poll<io::Result<usize>> {
        Pin::new(&mut self.get_mut().inner).poll_write(cx, b)
    }
    fn poll_flush(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        Pin::new(&mut self.get_mut().inner).poll_flush(cx)
    }
    fn poll_shutdown(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        Pin::new(&mut self.get_mut().inner).poll_shutdown(cx)
    }
}

pub struct VisionTlsStream<S> {
    tls: TlsStream<RecordStream<S>>,
    read_raw: Arc<AtomicBool>,
}
impl<S> VisionTlsStream<S> {
    pub fn new(tls: TlsStream<RecordStream<S>>, read_raw: Arc<AtomicBool>) -> Self {
        Self { tls, read_raw }
    }
}
impl<S: AsyncRead + AsyncWrite + Unpin> AsyncRead for VisionTlsStream<S> {
    fn poll_read(
        self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &mut ReadBuf<'_>,
    ) -> Poll<io::Result<()>> {
        let this = self.get_mut();
        if this.read_raw.load(Ordering::Acquire) {
            // Drain plaintext already decoded in the final encrypted record.
            let (transport, session) = this.tls.get_mut();
            match session.reader().read(buf.initialize_unfilled()) {
                Ok(n) if n > 0 => {
                    buf.advance(n);
                    return Poll::Ready(Ok(()));
                }
                Err(e) if e.kind() != io::ErrorKind::WouldBlock => return Poll::Ready(Err(e)),
                _ => {}
            }
            return Pin::new(&mut transport.inner).poll_read(cx, buf);
        }
        // tokio-rustls's AsyncRead fills the entire caller buffer by polling
        // successive records. Vision must inspect each plaintext chunk first:
        // the next bytes after command 2 are raw inner TLS, not outer TLS.
        match Pin::new(&mut this.tls).poll_fill_buf(cx) {
            Poll::Ready(Ok(data)) => {
                let n = data.len().min(buf.remaining());
                buf.put_slice(&data[..n]);
                Pin::new(&mut this.tls).consume(n);
                Poll::Ready(Ok(()))
            }
            result => result.map_ok(|_| ()),
        }
    }
}
impl<S: AsyncRead + AsyncWrite + Unpin> AsyncWrite for VisionTlsStream<S> {
    fn poll_write(self: Pin<&mut Self>, cx: &mut Context<'_>, b: &[u8]) -> Poll<io::Result<usize>> {
        Pin::new(&mut self.get_mut().tls).poll_write(cx, b)
    }
    fn poll_flush(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        Pin::new(&mut self.get_mut().tls).poll_flush(cx)
    }
    fn poll_shutdown(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        Pin::new(&mut self.get_mut().tls).poll_shutdown(cx)
    }
}
