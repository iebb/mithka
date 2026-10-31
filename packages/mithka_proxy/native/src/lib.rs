//! A TCP-only, in-process Leaf embed. No device routing, TUN or subprocesses.
use std::{
    collections::HashMap,
    ffi::{c_char, CStr},
    net::TcpListener,
    sync::{
        atomic::{AtomicBool, AtomicU32, Ordering},
        mpsc, Arc, LazyLock, Mutex,
    },
    thread::{self, JoinHandle},
    time::Duration,
};

/// Runtime ids are reserved (None) before the worker exists, so two starts can
/// never share one Leaf runtime id.
struct Registry {
    next: u16,
    workers: HashMap<u16, Option<JoinHandle<()>>>,
}

static RUNTIMES: LazyLock<Mutex<Registry>> = LazyLock::new(|| {
    Mutex::new(Registry {
        next: 0,
        workers: HashMap::new(),
    })
});

/// The HTTP port every engine in this process routes app HTTP and WebViews
/// through; 0 is direct. Desktop windows run separate Dart isolates.
static APP_HTTP_PORT: AtomicU32 = AtomicU32::new(0);

const ALLOWED: &[&str] = &[
    "shadowsocks",
    "trojan",
    "vmess",
    "vless",
    "tls",
    "ws",
    "chain",
];

/// Returns (runtime ID << 32 | SOCKS port << 16 | HTTP port), or a negative
/// error code. The caller runs this on a worker isolate. JSON never hits disk.
///
/// # Safety
/// `json` points to a NUL-terminated UTF-8 configuration for the duration of
/// this call. Neither the pointer nor any Dart callback survives the call.
#[no_mangle]
pub unsafe extern "C" fn mithka_proxy_start(json: *const c_char) -> i64 {
    if json.is_null() {
        return -1;
    }
    let Ok(input) = CStr::from_ptr(json).to_str() else {
        return -1;
    };
    start(input).unwrap_or_else(|code| code)
}

fn reserve() -> Result<u16, i64> {
    let mut registry = RUNTIMES.lock().map_err(|_| -3)?;
    for _ in 0..u16::MAX {
        registry.next = registry.next.checked_add(1).unwrap_or(1);
        let id = registry.next;
        // A runtime abandoned by a startup timeout may still hold its id.
        if !registry.workers.contains_key(&id) && !leaf::is_running(id) {
            registry.workers.insert(id, None);
            return Ok(id);
        }
    }
    Err(-3)
}

fn unreserve(id: u16) {
    if let Ok(mut registry) = RUNTIMES.lock() {
        registry.workers.remove(&id);
    }
}

fn start(input: &str) -> Result<i64, i64> {
    let mut config: serde_json::Value = serde_json::from_str(input).map_err(|_| -1)?;
    // This API accepts only generated outbound settings, never arbitrary Leaf
    // environment variables, listeners, routes or filesystem/log paths.
    let object = config.as_object().ok_or(-1)?;
    if object.keys().any(|k| k != "outbounds") {
        return Err(-1);
    }
    let outbounds = object
        .get("outbounds")
        .and_then(|o| o.as_array())
        .ok_or(-1)?;
    if outbounds.is_empty()
        || outbounds
            .iter()
            .any(|o| !matches!(o["protocol"].as_str(), Some(p) if ALLOWED.contains(&p)))
    {
        return Err(-1);
    }
    let socks = TcpListener::bind("127.0.0.1:0").map_err(|_| -2)?;
    let http = TcpListener::bind("127.0.0.1:0").map_err(|_| -2)?;
    socks.set_nonblocking(true).map_err(|_| -2)?;
    http.set_nonblocking(true).map_err(|_| -2)?;
    let socks_port = socks.local_addr().map_err(|_| -2)?.port();
    let http_port = http.local_addr().map_err(|_| -2)?.port();
    config["inbounds"] = serde_json::json!([
        {"tag": "mithka-socks", "protocol": "socks", "address": "127.0.0.1", "port": socks_port},
        {"tag": "mithka-http", "protocol": "http", "address": "127.0.0.1", "port": http_port}
    ]);
    config["log"] = serde_json::json!({"level": "none", "output": "console"});
    // Only the proxy server's own name is resolved here; destinations go to
    // the proxy by name. The OS resolver follows the device's DNS settings.
    config["dns"] = serde_json::json!({"servers": ["system"]});
    let id = reserve()?;
    let (tx, rx) = mpsc::sync_channel(1);
    let cancelled = Arc::new(AtomicBool::new(false));
    let cancel = cancelled.clone();
    let config = config.to_string();
    let spawned = thread::Builder::new()
        .name(format!("mithka-proxy-{id}"))
        .spawn(move || {
            let listeners =
                HashMap::from([("mithka-socks".into(), socks), ("mithka-http".into(), http)]);
            let opts = leaf::StartOptions {
                config: leaf::Config::Str(config),
                runtime_opt: leaf::RuntimeOption::SingleThread,
            };
            let _ = leaf::start_embedded(id, opts, listeners, || {
                let _ = tx.send(());
                if cancel.load(Ordering::Acquire) {
                    leaf::shutdown(id);
                }
            });
        });
    let worker = match spawned {
        Ok(worker) => worker,
        Err(_) => {
            unreserve(id);
            return Err(-3);
        }
    };
    if let Err(error) = rx.recv_timeout(Duration::from_secs(10)) {
        // A rejected configuration ends the worker, dropping the sender. A
        // stalled startup is latched so a runtime registering later stops.
        cancelled.store(true, Ordering::Release);
        leaf::shutdown(id);
        unreserve(id);
        return Err(match error {
            mpsc::RecvTimeoutError::Disconnected => -1,
            mpsc::RecvTimeoutError::Timeout => -4,
        });
    }
    let mut registry = RUNTIMES.lock().map_err(|_| -3)?;
    registry.workers.insert(id, Some(worker));
    Ok(((id as i64) << 32) | ((socks_port as i64) << 16) | http_port as i64)
}

/// False once the runtime ended, for instance because a listener failed after
/// the OS reclaimed it while the app was suspended.
#[no_mangle]
pub extern "C" fn mithka_proxy_is_running(id: u16) -> bool {
    let Ok(registry) = RUNTIMES.lock() else {
        return false;
    };
    matches!(registry.workers.get(&id), Some(Some(worker)) if !worker.is_finished())
}

/// Idempotent stop; waits for listeners and all owned connections to close.
#[no_mangle]
pub extern "C" fn mithka_proxy_stop(id: u16) {
    let worker = match RUNTIMES.lock() {
        Ok(mut registry) => match registry.workers.get(&id) {
            Some(Some(_)) => registry.workers.remove(&id).flatten(),
            _ => None,
        },
        Err(_) => None,
    };
    // The registry lock is not held while joining, so other runtimes can be
    // started, probed or stopped meanwhile.
    if let Some(worker) = worker {
        leaf::shutdown(id);
        let _ = worker.join();
    }
}

#[no_mangle]
pub extern "C" fn mithka_proxy_set_app_http_port(port: u16) {
    APP_HTTP_PORT.store(port as u32, Ordering::Release);
}

#[no_mangle]
pub extern "C" fn mithka_proxy_app_http_port() -> u16 {
    APP_HTTP_PORT.load(Ordering::Acquire) as u16
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{
        io::{Read, Write},
        net::TcpStream,
    };

    const SS: &str = r#"{"outbounds":[{"tag":"proxy","protocol":"shadowsocks","settings":{"address":"127.0.0.1","port":9,"method":"aes-128-gcm","password":"test"}}]}"#;

    fn ports(code: i64) -> (u16, u16, u16) {
        (
            (code >> 32) as u16,
            ((code >> 16) & 65535) as u16,
            (code & 65535) as u16,
        )
    }

    #[test]
    fn rejects_arbitrary_leaf_configs() {
        assert_eq!(
            start(r#"{"env":{"OUTBOUND_INTERFACE":"x"},"outbounds":[]}"#),
            Err(-1)
        );
        assert_eq!(start(r#"{"outbounds":[{"protocol":"direct"}]}"#), Err(-1));
        assert_eq!(
            start(r#"{"outbounds":[{"protocol":"shadowsocks"}],"dns":{}}"#),
            Err(-1)
        );
        assert_eq!(start("[]"), Err(-1));
        assert_eq!(start("bad"), Err(-1));
    }

    #[test]
    fn a_rejected_configuration_fails_fast() {
        let unknown = r#"{"outbounds":[{"tag":"proxy","protocol":"trojan","settings":{"address":"127.0.0.1","port":9,"password":"x","sni":"x"}}]}"#;
        assert_eq!(start(unknown), Err(-1));
    }

    #[test]
    fn binds_loopback_and_stops_all_listeners() {
        let (id, socks, http) = ports(start(SS).unwrap());
        assert_ne!(socks, http);
        assert!(mithka_proxy_is_running(id));
        assert!(TcpStream::connect(("127.0.0.1", socks)).is_ok());
        assert!(TcpStream::connect(("127.0.0.1", http)).is_ok());
        mithka_proxy_stop(id);
        mithka_proxy_stop(id);
        assert!(!mithka_proxy_is_running(id));
        assert!(TcpListener::bind(("127.0.0.1", socks)).is_ok());
        assert!(TcpListener::bind(("127.0.0.1", http)).is_ok());
    }

    #[test]
    fn runtimes_are_independent() {
        let (a, socks_a, _) = ports(start(SS).unwrap());
        let (b, socks_b, _) = ports(start(SS).unwrap());
        assert_ne!(a, b);
        mithka_proxy_stop(a);
        assert!(mithka_proxy_is_running(b));
        assert!(TcpStream::connect(("127.0.0.1", socks_a)).is_err());
        // The surviving runtime still completes a SOCKS5 greeting.
        let mut stream = TcpStream::connect(("127.0.0.1", socks_b)).unwrap();
        stream.write_all(&[5, 1, 0]).unwrap();
        let mut reply = [0u8; 2];
        stream.read_exact(&mut reply).unwrap();
        assert_eq!(reply, [5, 0]);
        mithka_proxy_stop(b);
    }

    #[test]
    fn app_port_is_process_wide() {
        mithka_proxy_set_app_http_port(4321);
        assert_eq!(mithka_proxy_app_http_port(), 4321);
        mithka_proxy_set_app_http_port(0);
        assert_eq!(mithka_proxy_app_http_port(), 0);
    }
}
