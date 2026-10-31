use std::io;

use async_trait::async_trait;
use tokio::io::AsyncWriteExt;
use uuid::Uuid;

use super::super::stream::{build_vless_tcp_header_with_flow, VlessStream};
use crate::{proxy::*, session::*};

pub struct Handler {
    pub flow: String,
    pub address: String,
    pub port: u16,
    pub uuid: String,
}

#[async_trait]
impl OutboundStreamHandler for Handler {
    fn connect_addr(&self) -> OutboundConnect {
        OutboundConnect::Proxy(Network::Tcp, self.address.clone(), self.port)
    }

    async fn handle<'a>(
        &'a self,
        sess: &'a Session,
        _lhs: Option<&mut AnyStream>,
        stream: Option<AnyStream>,
    ) -> io::Result<AnyStream> {
        tracing::trace!("handling outbound stream");
        let u = Uuid::parse_str(&self.uuid)
            .map_err(|e| io::Error::other(format!("parse uuid failed: {}", e)))?;
        let uuid_bytes = *u.as_bytes();

        let addr_type = match sess.destination.ip() {
            Some(ip) => {
                if ip.is_ipv4() {
                    1
                } else {
                    3
                }
            }
            None => 2,
        };
        let host = sess.destination.host();
        let port = sess.destination.port();

        let vision = match self.flow.as_str() {
            "" => false,
            "xtls-rprx-vision" => true,
            _ => {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidInput,
                    "unsupported VLESS flow",
                ))
            }
        };
        let header = build_vless_tcp_header_with_flow(&uuid_bytes, &host, port, addr_type, vision);

        let mut stream = stream.ok_or_else(|| io::Error::other("invalid input"))?;
        stream.write_all(&header).await?;

        // The VLESS response prefix precedes any Vision framing. Reading it is
        // deferred until the peer responds, so request-first protocols work.
        Ok(Box::new(VlessStream::client(
            stream,
            uuid_bytes,
            vision,
            sess.vision_read_raw.clone(),
        )))
    }
}
