//! Bindings to rootshell's host functions (modules `rootshell_socket` and
//! `rootshell_terminal`) and safe wrappers around them. Every call blocks
//! until the host has an answer; there is no poll or select.

use std::io;
use std::net::Ipv4Addr;
use std::pin::Pin;
use std::task::{Context, Poll};

use tokio::io::{AsyncRead, AsyncWrite, ReadBuf};

use crate::abi::{self, errno_text, AF_INET, SHUT_WR, SOCKADDR_MAX};

#[link(wasm_import_module = "rootshell_socket")]
extern "C" {
    fn rootshell_socket_socket(domain: i32, ty: i32, fd_out: *mut i32) -> i32;
    fn rootshell_socket_bind(fd: i32, addr: *const u8, addrlen: i32) -> i32;
    fn rootshell_socket_listen(fd: i32, backlog: i32) -> i32;
    fn rootshell_socket_accept(fd: i32, fd_out: *mut i32) -> i32;
    fn rootshell_socket_connect(fd: i32, addr: *const u8, addrlen: i32) -> i32;
    fn rootshell_socket_send(fd: i32, buf: *const u8, len: i32, sent_out: *mut u32) -> i32;
    fn rootshell_socket_recv(fd: i32, buf: *mut u8, len: i32, recv_out: *mut u32) -> i32;
    fn rootshell_socket_sendto(
        fd: i32,
        buf: *const u8,
        len: i32,
        addr: *const u8,
        addrlen: i32,
        sent_out: *mut u32,
    ) -> i32;
    fn rootshell_socket_shutdown(fd: i32, how: i32) -> i32;
    fn rootshell_socket_close(fd: i32) -> i32;
    fn rootshell_socket_getsockname(fd: i32, addr_out: *mut u8, addrlen_io: *mut i32) -> i32;
}

#[link(wasm_import_module = "rootshell_terminal")]
extern "C" {
    fn rootshell_terminal_set_raw(enabled: i32) -> i32;
}

/// Puts the terminal in cooked mode, where Ctrl-C ends the program.
pub fn cooked_terminal() {
    unsafe {
        rootshell_terminal_set_raw(0);
    }
}

fn check(rc: i32) -> Result<(), i32> {
    if rc == 0 {
        Ok(())
    } else {
        Err(rc)
    }
}

pub fn io_err(e: i32) -> io::Error {
    io::Error::other(errno_text(e))
}

/// A host socket descriptor, closed on drop.
#[derive(Debug)]
pub struct Socket(i32);

impl Socket {
    pub fn new(ty: i32) -> Result<Self, i32> {
        let mut fd = -1;
        check(unsafe { rootshell_socket_socket(AF_INET, ty, &mut fd) })?;
        Ok(Socket(fd))
    }

    pub fn bind(&self, ip: Ipv4Addr, port: u16) -> Result<(), i32> {
        let a = abi::sockaddr_in(ip, port);
        check(unsafe { rootshell_socket_bind(self.0, a.as_ptr(), a.len() as i32) })
    }

    pub fn listen(&self, backlog: i32) -> Result<(), i32> {
        check(unsafe { rootshell_socket_listen(self.0, backlog) })
    }

    pub fn accept(&self) -> Result<Socket, i32> {
        let mut fd = -1;
        check(unsafe { rootshell_socket_accept(self.0, &mut fd) })?;
        Ok(Socket(fd))
    }

    pub fn connect(&self, ip: Ipv4Addr, port: u16) -> Result<(), i32> {
        let a = abi::sockaddr_in(ip, port);
        check(unsafe { rootshell_socket_connect(self.0, a.as_ptr(), a.len() as i32) })
    }

    pub fn send(&self, buf: &[u8]) -> Result<usize, i32> {
        let mut sent = 0u32;
        let len = buf.len().min(i32::MAX as usize) as i32;
        check(unsafe { rootshell_socket_send(self.0, buf.as_ptr(), len, &mut sent) })?;
        Ok(sent as usize)
    }

    pub fn send_all(&self, mut buf: &[u8]) -> Result<(), i32> {
        while !buf.is_empty() {
            let n = self.send(buf)?;
            if n == 0 {
                return Err(29); // EIO: the host accepted nothing
            }
            buf = &buf[n..];
        }
        Ok(())
    }

    pub fn recv(&self, buf: &mut [u8]) -> Result<usize, i32> {
        let mut got = 0u32;
        let len = buf.len().min(i32::MAX as usize) as i32;
        check(unsafe { rootshell_socket_recv(self.0, buf.as_mut_ptr(), len, &mut got) })?;
        Ok(got as usize)
    }

    pub fn send_to(&self, buf: &[u8], ip: Ipv4Addr, port: u16) -> Result<usize, i32> {
        let a = abi::sockaddr_in(ip, port);
        let mut sent = 0u32;
        check(unsafe {
            rootshell_socket_sendto(
                self.0,
                buf.as_ptr(),
                buf.len() as i32,
                a.as_ptr(),
                a.len() as i32,
                &mut sent,
            )
        })?;
        Ok(sent as usize)
    }

    pub fn shutdown_write(&self) -> Result<(), i32> {
        check(unsafe { rootshell_socket_shutdown(self.0, SHUT_WR) })
    }

    /// The local IPv4 address and port, if the host reports one.
    pub fn local_addr(&self) -> Option<(Ipv4Addr, u16)> {
        let mut buf = [0u8; SOCKADDR_MAX];
        let mut len = buf.len() as i32;
        check(unsafe { rootshell_socket_getsockname(self.0, buf.as_mut_ptr(), &mut len) }).ok()?;
        let len = (len.max(0) as usize).min(buf.len());
        abi::parse_sockaddr_in(&buf[..len])
    }
}

impl Drop for Socket {
    fn drop(&mut self) {
        unsafe {
            rootshell_socket_close(self.0);
        }
    }
}

/// A connected TCP socket usable by tokio code. Each poll makes the blocking
/// host call and returns `Ready`, which is fine with a single task.
#[derive(Debug)]
pub struct TcpConn(pub Socket);

impl AsyncRead for TcpConn {
    fn poll_read(
        self: Pin<&mut Self>,
        _cx: &mut Context<'_>,
        buf: &mut ReadBuf<'_>,
    ) -> Poll<io::Result<()>> {
        let dst = buf.initialize_unfilled();
        if dst.is_empty() {
            return Poll::Ready(Ok(()));
        }
        match self.0.recv(dst) {
            Ok(n) => {
                buf.advance(n);
                Poll::Ready(Ok(()))
            }
            Err(e) => Poll::Ready(Err(io_err(e))),
        }
    }
}

impl AsyncWrite for TcpConn {
    fn poll_write(
        self: Pin<&mut Self>,
        _cx: &mut Context<'_>,
        buf: &[u8],
    ) -> Poll<io::Result<usize>> {
        Poll::Ready(self.0.send(buf).map_err(io_err))
    }

    fn poll_flush(self: Pin<&mut Self>, _cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        Poll::Ready(Ok(()))
    }

    fn poll_shutdown(self: Pin<&mut Self>, _cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        Poll::Ready(self.0.shutdown_write().map_err(io_err))
    }
}

/// Opens a TCP socket bound to `ip:port` and listening.
pub fn tcp_listen(ip: Ipv4Addr, port: u16) -> Result<Socket, String> {
    let s = Socket::new(abi::SOCK_STREAM).map_err(|e| format!("socket: {}", errno_text(e)))?;
    s.bind(ip, port)
        .map_err(|e| format!("bind {ip}:{port}: {}", errno_text(e)))?;
    s.listen(4)
        .map_err(|e| format!("listen {ip}:{port}: {}", errno_text(e)))?;
    Ok(s)
}

/// Sends one datagram from a fresh UDP socket.
pub fn udp_send_once(payload: &[u8], ip: Ipv4Addr, port: u16) -> Result<(), String> {
    let s = Socket::new(abi::SOCK_DGRAM).map_err(|e| format!("udp socket: {}", errno_text(e)))?;
    s.send_to(payload, ip, port)
        .map_err(|e| format!("sendto {ip}:{port}: {}", errno_text(e)))?;
    Ok(())
}

/// Asks the host which local address it would use toward `ip:port`: first by
/// connecting a UDP socket, then, if that gives nothing and a `probe` is
/// given, by sending it.
pub fn route_source(ip: Ipv4Addr, port: u16, probe: Option<&[u8]>) -> Option<Ipv4Addr> {
    let s = Socket::new(abi::SOCK_DGRAM).ok()?;
    if s.connect(ip, port).is_ok() {
        if let Some((local, _)) = s.local_addr() {
            if !local.is_unspecified() {
                return Some(local);
            }
        }
    }
    drop(s);
    let probe = probe?;
    let s = Socket::new(abi::SOCK_DGRAM).ok()?;
    s.send_to(probe, ip, port).ok()?;
    s.local_addr().map(|(local, _)| local).filter(|l| !l.is_unspecified())
}
