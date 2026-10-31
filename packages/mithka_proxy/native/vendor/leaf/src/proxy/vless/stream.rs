//! Mithka's TCP-only VLESS and Vision framing. Vision ends outbound padding
//! after the first block; inbound direct-copy transitions are handled by TLS.
use std::{
    io,
    pin::Pin,
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc,
    },
    task::{Context, Poll},
};
use tokio::io::{AsyncRead, AsyncWrite, ReadBuf};

pub fn build_vless_tcp_header_with_flow(
    uuid: &[u8; 16],
    host: &str,
    port: u16,
    kind: u8,
    vision: bool,
) -> Vec<u8> {
    let mut h = vec![0];
    h.extend_from_slice(uuid);
    if vision {
        h.extend_from_slice(b"\x12\x0a\x10xtls-rprx-vision");
    } else {
        h.push(0);
    }
    h.push(1);
    h.extend_from_slice(&port.to_be_bytes());
    h.push(kind);
    match kind {
        1 => h.extend_from_slice(&host.parse::<std::net::Ipv4Addr>().unwrap().octets()),
        3 => h.extend_from_slice(&host.parse::<std::net::Ipv6Addr>().unwrap().octets()),
        _ => {
            h.push(host.len() as u8);
            h.extend_from_slice(host.as_bytes());
        }
    }
    h
}

// Kept for the upstream REALITY module, which the Mithka build excludes.
pub fn build_vless_tcp_header(uuid: &[u8; 16], host: &str, port: u16, kind: u8) -> Vec<u8> {
    build_vless_tcp_header_with_flow(uuid, host, port, kind, true)
}

pub struct VlessStream<S> {
    stream: S,
    uuid: [u8; 16],
    vision: bool,
    prefix: Vec<u8>,
    response_done: bool,
    response_skip: usize,
    uuid_read: usize,
    header: Vec<u8>,
    content: usize,
    padding: usize,
    command: u8,
    ended: bool,
    read_raw: Arc<AtomicBool>,
    plain: Vec<u8>,
    write_buf: Vec<u8>,
    write_pos: usize,
    write_len: usize,
    wrote_first: bool,
}

impl<S> VlessStream<S> {
    pub fn client(stream: S, uuid: [u8; 16], vision: bool, read_raw: Arc<AtomicBool>) -> Self {
        Self {
            stream,
            uuid,
            vision,
            prefix: Vec::new(),
            response_done: false,
            response_skip: 0,
            uuid_read: 0,
            header: Vec::new(),
            content: 0,
            padding: 0,
            command: 0,
            ended: !vision,
            read_raw,
            plain: Vec::new(),
            write_buf: Vec::new(),
            write_pos: 0,
            write_len: 0,
            wrote_first: false,
        }
    }
    pub fn new(stream: S, uuid: [u8; 16], read_raw: Option<Arc<AtomicBool>>) -> Self {
        Self::client(stream, uuid, true, read_raw.unwrap_or_default())
    }
    fn decode(&mut self, bytes: &[u8]) -> io::Result<()> {
        for &b in bytes {
            if !self.response_done {
                if self.prefix.len() < 2 {
                    self.prefix.push(b);
                    if self.prefix.len() == 1 && b != 0 {
                        return Err(io::Error::new(
                            io::ErrorKind::InvalidData,
                            "invalid VLESS response",
                        ));
                    }
                    if self.prefix.len() == 2 {
                        self.response_skip = b as usize;
                        self.response_done = b == 0;
                    }
                } else {
                    self.response_skip -= 1;
                    self.response_done = self.response_skip == 0;
                }
                continue;
            }
            if self.ended {
                self.plain.push(b);
                continue;
            }
            if self.uuid_read < 16 {
                if b != self.uuid[self.uuid_read] {
                    return Err(io::Error::new(
                        io::ErrorKind::InvalidData,
                        "invalid Vision UUID",
                    ));
                }
                self.uuid_read += 1;
                continue;
            }
            if self.header.len() < 5 {
                self.header.push(b);
                if self.header.len() != 5 {
                    continue;
                }
                self.command = self.header[0];
                if self.command > 2 {
                    return Err(io::Error::new(
                        io::ErrorKind::InvalidData,
                        "invalid Vision command",
                    ));
                }
                self.content = u16::from_be_bytes([self.header[1], self.header[2]]) as usize;
                self.padding = u16::from_be_bytes([self.header[3], self.header[4]]) as usize;
            } else if self.content > 0 {
                self.content -= 1;
                self.plain.push(b);
            } else if self.padding > 0 {
                self.padding -= 1;
            }
            if self.header.len() == 5 && self.content == 0 && self.padding == 0 {
                if self.command != 0 {
                    self.ended = true;
                    if self.command == 2 {
                        self.read_raw.store(true, Ordering::Release);
                    }
                }
                self.header.clear();
            }
        }
        Ok(())
    }
}

impl<S: AsyncRead + AsyncWrite + Unpin> AsyncRead for VlessStream<S> {
    fn poll_read(
        self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &mut ReadBuf<'_>,
    ) -> Poll<io::Result<()>> {
        let this = self.get_mut();
        if buf.remaining() == 0 {
            return Poll::Ready(Ok(()));
        }
        loop {
            if !this.plain.is_empty() {
                let n = buf.remaining().min(this.plain.len());
                buf.put_slice(&this.plain[..n]);
                this.plain.drain(..n);
                return Poll::Ready(Ok(()));
            }
            let mut data = [0u8; 16384];
            let mut read = ReadBuf::new(&mut data);
            match Pin::new(&mut this.stream).poll_read(cx, &mut read) {
                Poll::Ready(Ok(())) => {
                    if read.filled().is_empty() {
                        if !this.response_done
                            || (!this.ended
                                && (this.content != 0
                                    || this.padding != 0
                                    || !this.header.is_empty()))
                        {
                            return Poll::Ready(Err(io::Error::new(
                                io::ErrorKind::UnexpectedEof,
                                "truncated VLESS response",
                            )));
                        }
                        return Poll::Ready(Ok(()));
                    }
                    if let Err(e) = this.decode(read.filled()) {
                        return Poll::Ready(Err(e));
                    }
                }
                result => return result,
            }
        }
    }
}

impl<S: AsyncRead + AsyncWrite + Unpin> AsyncWrite for VlessStream<S> {
    fn poll_write(
        self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &[u8],
    ) -> Poll<io::Result<usize>> {
        let this = self.get_mut();
        if this.wrote_first || !this.vision {
            return Pin::new(&mut this.stream).poll_write(cx, buf);
        }
        if buf.is_empty() {
            return Poll::Ready(Ok(0));
        }
        if this.write_buf.is_empty() {
            this.write_len = buf.len().min(16384);
            this.write_buf.extend_from_slice(&this.uuid);
            // End padding without requesting direct copy on the write side.
            this.write_buf.push(1);
            this.write_buf
                .extend_from_slice(&(this.write_len as u16).to_be_bytes());
            this.write_buf.extend_from_slice(&[0, 0]);
            this.write_buf.extend_from_slice(&buf[..this.write_len]);
        }
        while this.write_pos < this.write_buf.len() {
            match Pin::new(&mut this.stream).poll_write(cx, &this.write_buf[this.write_pos..]) {
                Poll::Ready(Ok(0)) => return Poll::Ready(Err(io::ErrorKind::WriteZero.into())),
                Poll::Ready(Ok(n)) => this.write_pos += n,
                Poll::Ready(Err(e)) => return Poll::Ready(Err(e)),
                Poll::Pending => return Poll::Pending,
            }
        }
        this.wrote_first = true;
        this.write_buf.clear();
        Poll::Ready(Ok(this.write_len))
    }
    fn poll_flush(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        Pin::new(&mut self.get_mut().stream).poll_flush(cx)
    }
    fn poll_shutdown(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        Pin::new(&mut self.get_mut().stream).poll_shutdown(cx)
    }
}
