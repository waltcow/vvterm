use super::*;
use crate::core::{ClientEvent, HerdrClientCore};
use crate::protocol::{decode_client_message, ClientMessage};

#[cfg(target_os = "macos")]
use std::io::{Read, Write};
#[cfg(target_os = "macos")]
use std::process::{Command, Stdio};
#[cfg(target_os = "macos")]
use std::sync::mpsc;
#[cfg(target_os = "macos")]
use std::time::Duration;

fn welcome_frame() -> Vec<u8> {
    vec![4, 0, 0, 0, 0, 16, 1, 0]
}

fn first_ansi_frame() -> Vec<u8> {
    vec![
        10, 0, 0, 0, // payload length
        2, // ServerMessage::Terminal
        1, // seq
        120, 40, // width, height
        1,  // full
        4,  // byte vector length
        0x1b, 0x5b, 0x32, 0x4a,
    ]
}

fn activate(client: &mut HerdrClientCore) {
    client
        .feed(&welcome_frame())
        .expect("welcome should decode");
    assert_eq!(
        client.next_event(),
        Some(ClientEvent::Welcome { version: 16 })
    );
}

fn payload(frame: &[u8]) -> &[u8] {
    let length = u32::from_le_bytes(frame[..4].try_into().expect("header")) as usize;
    assert_eq!(frame.len(), 4 + length);
    &frame[4..]
}

#[test]
fn hello_matches_protocol_16_golden_bytes() {
    let mut client = HerdrClientCore::new(80, 24).expect("client");
    let hello = client.take_outbound().expect("hello");

    assert_eq!(hello, vec![9, 0, 0, 0, 0, 16, 80, 24, 0, 0, 1, 0, 0]);
    assert_eq!(
        decode_client_message(payload(&hello)).expect("decode hello"),
        ClientMessage::Hello {
            version: 16,
            cols: 80,
            rows: 24,
            cell_width_px: 0,
            cell_height_px: 0,
            requested_encoding: crate::protocol::RenderEncoding::TerminalAnsi,
            keybindings: crate::protocol::ClientKeybindings::Server,
            launch_mode: crate::protocol::ClientLaunchMode::App,
        }
    );
}

#[test]
fn fragmented_welcome_and_ansi_produce_typed_events() {
    let mut client = HerdrClientCore::new(80, 24).expect("client");
    let _ = client.take_outbound();

    client.feed(&welcome_frame()[..3]).expect("partial header");
    assert_eq!(client.next_event(), None);
    client
        .feed(&welcome_frame()[3..])
        .expect("welcome remainder");
    assert_eq!(
        client.next_event(),
        Some(ClientEvent::Welcome { version: 16 })
    );

    let ansi = first_ansi_frame();
    for byte in ansi {
        client.feed(&[byte]).expect("fragmented ansi byte");
    }
    assert_eq!(
        client.next_event(),
        Some(ClientEvent::Ansi(crate::protocol::TerminalFrame {
            seq: 1,
            width: 120,
            height: 40,
            full: true,
            bytes: vec![0x1b, 0x5b, 0x32, 0x4a],
        }))
    );
}

#[test]
fn input_resize_and_detach_match_golden_bytes() {
    let mut client = HerdrClientCore::new(80, 24).expect("client");
    let _ = client.take_outbound();
    activate(&mut client);

    client
        .send_input(&[0, 10, 13, 27, 255])
        .expect("input should encode");
    assert_eq!(
        client.take_outbound().expect("input"),
        vec![7, 0, 0, 0, 1, 5, 0, 10, 13, 27, 255]
    );

    client.resize(120, 40).expect("resize should encode");
    assert_eq!(
        client.take_outbound().expect("resize"),
        vec![5, 0, 0, 0, 3, 120, 40, 0, 0]
    );

    client.detach().expect("detach should encode");
    assert_eq!(client.take_outbound().expect("detach"), vec![1, 0, 0, 0, 4]);
    assert!(client.send_input(b"late").is_err());
}

#[test]
fn rejects_protocol_mismatch_and_non_full_first_frame() {
    let mut mismatch = HerdrClientCore::new(80, 24).expect("client");
    let _ = mismatch.take_outbound();
    let wrong_welcome = vec![4, 0, 0, 0, 0, 17, 1, 0];
    assert!(mismatch
        .feed(&wrong_welcome)
        .expect_err("mismatch")
        .contains("protocol mismatch"));

    let mut incremental = HerdrClientCore::new(80, 24).expect("client");
    let _ = incremental.take_outbound();
    activate(&mut incremental);
    let mut frame = first_ansi_frame();
    frame[8] = 0;
    assert!(incremental
        .feed(&frame)
        .expect_err("first frame must be full")
        .contains("must be full sequence 1"));
}

#[test]
fn rejects_sequence_gaps_and_oversized_frames() {
    let mut client = HerdrClientCore::new(80, 24).expect("client");
    let _ = client.take_outbound();
    activate(&mut client);
    client.feed(&first_ansi_frame()).expect("first frame");
    let _ = client.next_event();

    let mut gap = first_ansi_frame();
    gap[5] = 3;
    gap[8] = 0;
    assert!(client
        .feed(&gap)
        .expect_err("sequence gap")
        .contains("expected 2, got 3"));

    let mut oversized = HerdrClientCore::new(80, 24).expect("client");
    let _ = oversized.take_outbound();
    let claimed = (crate::protocol::MAX_FRAME_SIZE as u32 + 1).to_le_bytes();
    assert!(oversized
        .feed(&claimed)
        .expect_err("oversized frame")
        .contains("exceeds maximum"));
}

#[test]
fn c_abi_transfers_and_frees_owned_buffers() {
    unsafe {
        assert_eq!(herdr_client_protocol_version(), 16);
        let client = herdr_client_new(80, 24);
        assert!(!client.is_null());

        let mut outbound = HerdrBuffer::default();
        assert_eq!(
            herdr_client_take_outbound(client, &mut outbound),
            HERDR_STATUS_OK
        );
        assert_eq!(
            slice::from_raw_parts(outbound.ptr, outbound.len)[..4],
            [9, 0, 0, 0]
        );
        herdr_buffer_free(&mut outbound);
        assert!(outbound.ptr.is_null());

        let welcome = welcome_frame();
        assert_eq!(
            herdr_client_feed(client, welcome.as_ptr(), welcome.len()),
            HERDR_STATUS_OK
        );
        let mut event = HerdrEvent::default();
        assert_eq!(herdr_client_next_event(client, &mut event), HERDR_STATUS_OK);
        assert_eq!(event.kind, HERDR_EVENT_WELCOME);
        assert_eq!(event.sequence, 16);
        herdr_event_free(&mut event);

        assert_eq!(herdr_client_resize(client, 0, 24), HERDR_STATUS_ERROR);
        let mut error = HerdrBuffer::default();
        assert_eq!(herdr_client_take_error(client, &mut error), HERDR_STATUS_OK);
        let error_text = String::from_utf8_lossy(slice::from_raw_parts(error.ptr, error.len));
        assert!(error_text.contains("greater than zero"));
        herdr_buffer_free(&mut error);

        herdr_client_free(client);
    }
}

#[cfg(target_os = "macos")]
#[test]
#[ignore = "requires Herdr v0.7.4 locally or an authenticated SSH control socket"]
fn installed_bridge_completes_real_handshake_and_full_redraw() {
    let herdr = std::env::var("HERDR_BIN").unwrap_or_else(|_| "herdr".to_owned());
    let session = format!("vvterm-client-kit-smoke-{}", std::process::id());
    let ssh = std::env::var("HERDR_BRIDGE_SSH_SOCKET")
        .ok()
        .zip(std::env::var("HERDR_BRIDGE_SSH_TARGET").ok());
    let remote_herdr = std::env::var("HERDR_REMOTE_BIN").unwrap_or_else(|_| "herdr".to_owned());
    let mut bridge_command = if let Some((socket, target)) = &ssh {
        let mut command = Command::new("ssh");
        command.args([
            "-S",
            socket,
            target,
            &format!("{remote_herdr} --session {session} remote-client-bridge"),
        ]);
        command
    } else {
        let mut command = Command::new(&herdr);
        command.args(["--session", &session, "remote-client-bridge"]);
        command
    };
    let mut child = bridge_command
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("start installed Herdr bridge");

    let mut stdin = child.stdin.take().expect("bridge stdin");
    let mut stdout = child.stdout.take().expect("bridge stdout");
    let mut stderr = child.stderr.take().expect("bridge stderr");
    let (frames_tx, frames_rx) = mpsc::channel();
    let reader = std::thread::spawn(move || loop {
        let mut header = [0_u8; 4];
        if let Err(error) = stdout.read_exact(&mut header) {
            let _ = frames_tx.send(Err(format!("read bridge frame header: {error}")));
            break;
        }
        let length = u32::from_le_bytes(header) as usize;
        if length == 0 || length > crate::protocol::MAX_FRAME_SIZE {
            let _ = frames_tx.send(Err(format!("invalid bridge frame length {length}")));
            break;
        }
        let mut payload = vec![0_u8; length];
        if let Err(error) = stdout.read_exact(&mut payload) {
            let _ = frames_tx.send(Err(format!("read bridge frame payload: {error}")));
            break;
        }
        let frame = header.into_iter().chain(payload).collect::<Vec<_>>();
        if frames_tx.send(Ok(frame)).is_err() {
            break;
        }
    });

    let result = (|| -> Result<(), String> {
        let mut client = HerdrClientCore::new(80, 24)?;
        let hello = client
            .take_outbound()
            .ok_or_else(|| "client did not queue Hello".to_owned())?;
        stdin.write_all(&hello).map_err(|error| error.to_string())?;
        stdin.flush().map_err(|error| error.to_string())?;

        let mut saw_welcome = false;
        let mut saw_full_redraw = false;
        for _ in 0..16 {
            let frame = frames_rx
                .recv_timeout(Duration::from_secs(10))
                .map_err(|error| format!("waiting for bridge frame: {error}"))??;
            client.feed(&frame)?;
            while let Some(event) = client.next_event() {
                match event {
                    ClientEvent::Welcome { version } => saw_welcome = version == 16,
                    ClientEvent::Ansi(frame) => {
                        if frame.seq == 1 && frame.full {
                            saw_full_redraw = true;
                        }
                    }
                    ClientEvent::Graphics(_) | ClientEvent::Shutdown { .. } => {}
                }
            }
            if saw_welcome && saw_full_redraw {
                client.resize(100, 30)?;
                client.send_input(b"\x1b")?;
                client.detach()?;
                while let Some(outbound) = client.take_outbound() {
                    stdin
                        .write_all(&outbound)
                        .map_err(|error| error.to_string())?;
                }
                stdin.flush().map_err(|error| error.to_string())?;
                return Ok(());
            }
        }
        Err(format!(
            "bridge did not produce required events: welcome={saw_welcome}, full_redraw={saw_full_redraw}"
        ))
    })();

    drop(stdin);
    let _ = child.kill();
    let _ = child.wait();
    let mut diagnostics = String::new();
    let _ = stderr.read_to_string(&mut diagnostics);
    let _ = reader.join();
    let mut stop_command = if let Some((socket, target)) = ssh {
        let mut command = Command::new("ssh");
        command.args([
            "-S",
            &socket,
            &target,
            &format!("{remote_herdr} --session {session} server stop"),
        ]);
        command
    } else {
        let mut command = Command::new(&herdr);
        command.args(["--session", &session, "server", "stop"]);
        command
    };
    let _ = stop_command
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();

    result
        .map_err(|error| {
            if diagnostics.trim().is_empty() {
                error
            } else {
                format!("{error}; bridge stderr: {}", diagnostics.trim())
            }
        })
        .expect("real Herdr bridge smoke test");
}
