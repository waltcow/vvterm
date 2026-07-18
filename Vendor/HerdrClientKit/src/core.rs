use std::collections::VecDeque;

use crate::protocol::{
    decode_server_message, encode_framed, AttachScrollDirection, AttachScrollSource,
    ClientKeybindings, ClientLaunchMode, ClientMessage, RenderEncoding, ServerMessage,
    TerminalFrame, MAX_FRAME_SIZE, PROTOCOL_VERSION,
};

const MAX_FEED_BYTES: usize = 256 * 1024;
const MAX_QUEUED_EVENTS: usize = 256;
const MAX_QUEUED_EVENT_BYTES: usize = 8 * 1024 * 1024;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ClientState {
    AwaitingWelcome,
    Active,
    Closed,
    Failed,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ClientEvent {
    Welcome { version: u32 },
    Ansi(TerminalFrame),
    Graphics(Vec<u8>),
    Shutdown { reason: Option<String> },
}

impl ClientEvent {
    fn data_len(&self) -> usize {
        match self {
            Self::Welcome { .. } => 0,
            Self::Ansi(frame) => frame.bytes.len(),
            Self::Graphics(bytes) => bytes.len(),
            Self::Shutdown { reason } => reason.as_ref().map_or(0, String::len),
        }
    }
}

pub struct HerdrClientCore {
    inbound: Vec<u8>,
    outbound: VecDeque<Vec<u8>>,
    events: VecDeque<ClientEvent>,
    queued_event_bytes: usize,
    state: ClientState,
    last_sequence: Option<u64>,
    last_error: Option<String>,
}

impl HerdrClientCore {
    pub fn new(cols: u16, rows: u16) -> Result<Self, String> {
        if cols == 0 || rows == 0 {
            return Err("terminal dimensions must be greater than zero".to_owned());
        }

        let hello = ClientMessage::Hello {
            version: PROTOCOL_VERSION,
            cols,
            rows,
            cell_width_px: 0,
            cell_height_px: 0,
            requested_encoding: RenderEncoding::TerminalAnsi,
            keybindings: ClientKeybindings::Server,
            launch_mode: ClientLaunchMode::App,
        };
        let mut outbound = VecDeque::new();
        outbound.push_back(encode_framed(&hello)?);

        Ok(Self {
            inbound: Vec::new(),
            outbound,
            events: VecDeque::new(),
            queued_event_bytes: 0,
            state: ClientState::AwaitingWelcome,
            last_sequence: None,
            last_error: None,
        })
    }

    pub fn feed(&mut self, bytes: &[u8]) -> Result<(), String> {
        self.require_not_terminal()?;
        if bytes.len() > MAX_FEED_BYTES {
            return self.fail(format!(
                "feed chunk {} exceeds maximum {}",
                bytes.len(),
                MAX_FEED_BYTES
            ));
        }
        self.inbound.extend_from_slice(bytes);

        loop {
            if self.inbound.len() < 4 {
                return Ok(());
            }
            let length = u32::from_le_bytes(
                self.inbound[..4]
                    .try_into()
                    .map_err(|_| "invalid frame header".to_owned())?,
            ) as usize;
            if length == 0 {
                return self.fail("zero-length protocol frame".to_owned());
            }
            if length > MAX_FRAME_SIZE {
                return self.fail(format!("frame {length} exceeds maximum {MAX_FRAME_SIZE}"));
            }
            if self.inbound.len() < 4 + length {
                if self.inbound.len() > 4 + MAX_FRAME_SIZE {
                    return self.fail("inbound buffer exceeds frame bound".to_owned());
                }
                return Ok(());
            }

            let payload = self.inbound[4..4 + length].to_vec();
            self.inbound.drain(..4 + length);
            let message = match decode_server_message(&payload) {
                Ok(message) => message,
                Err(error) => return self.fail(error),
            };
            if let Err(error) = self.handle_server_message(message) {
                return self.fail(error);
            }
        }
    }

    pub fn send_input(&mut self, bytes: &[u8]) -> Result<(), String> {
        self.require_active()?;
        self.queue_outbound(ClientMessage::Input {
            data: bytes.to_vec(),
        })
    }

    pub fn resize(&mut self, cols: u16, rows: u16) -> Result<(), String> {
        self.require_active()?;
        if cols == 0 || rows == 0 {
            return Err("terminal dimensions must be greater than zero".to_owned());
        }
        self.queue_outbound(ClientMessage::Resize {
            cols,
            rows,
            cell_width_px: 0,
            cell_height_px: 0,
        })
    }

    pub fn scroll(&mut self, direction: AttachScrollDirection, lines: u16) -> Result<(), String> {
        self.require_active()?;
        if lines == 0 {
            return Err("scroll lines must be greater than zero".to_owned());
        }
        self.queue_outbound(ClientMessage::AttachScroll {
            source: AttachScrollSource::Wheel,
            direction,
            lines,
            column: None,
            row: None,
            modifiers: 0,
        })
    }

    pub fn detach(&mut self) -> Result<(), String> {
        self.require_active()?;
        self.queue_outbound(ClientMessage::Detach)?;
        self.state = ClientState::Closed;
        Ok(())
    }

    pub fn take_outbound(&mut self) -> Option<Vec<u8>> {
        self.outbound.pop_front()
    }

    pub fn next_event(&mut self) -> Option<ClientEvent> {
        let event = self.events.pop_front()?;
        self.queued_event_bytes = self.queued_event_bytes.saturating_sub(event.data_len());
        Some(event)
    }

    pub fn take_error(&mut self) -> Option<String> {
        self.last_error.take()
    }

    pub fn record_ffi_error(&mut self, error: String) {
        self.last_error = Some(error);
    }

    fn handle_server_message(&mut self, message: ServerMessage) -> Result<(), String> {
        if self.state == ClientState::AwaitingWelcome {
            return match message {
                ServerMessage::Welcome {
                    version,
                    encoding,
                    error,
                } => {
                    if let Some(error) = error {
                        return Err(format!("handshake rejected: {error}"));
                    }
                    if version != PROTOCOL_VERSION {
                        return Err(format!(
                            "protocol mismatch: client {PROTOCOL_VERSION}, server {version}"
                        ));
                    }
                    if encoding != RenderEncoding::TerminalAnsi {
                        return Err(format!("unsupported render encoding: {encoding:?}"));
                    }
                    self.state = ClientState::Active;
                    self.push_event(ClientEvent::Welcome { version })
                }
                _ => Err("expected Welcome as first server message".to_owned()),
            };
        }

        if self.state != ClientState::Active {
            return Err("server message received after client closed".to_owned());
        }

        match message {
            ServerMessage::Welcome { .. } => Err("duplicate Welcome message".to_owned()),
            ServerMessage::Terminal(frame) => self.handle_terminal_frame(frame),
            ServerMessage::Graphics { bytes } => self.push_event(ClientEvent::Graphics(bytes)),
            ServerMessage::ServerShutdown { reason } => {
                self.state = ClientState::Closed;
                self.push_event(ClientEvent::Shutdown { reason })
            }
            ServerMessage::Frame(_) => {
                Err("semantic frame received after TerminalAnsi negotiation".to_owned())
            }
            ServerMessage::Notify { .. }
            | ServerMessage::Clipboard { .. }
            | ServerMessage::WindowTitle { .. }
            | ServerMessage::ReloadSoundConfig
            | ServerMessage::MouseCapture { .. }
            | ServerMessage::PrefixInputSource { .. } => Ok(()),
        }
    }

    fn handle_terminal_frame(&mut self, frame: TerminalFrame) -> Result<(), String> {
        if frame.width == 0 || frame.height == 0 {
            return Err("terminal frame dimensions must be greater than zero".to_owned());
        }
        match self.last_sequence {
            None => {
                if frame.seq != 1 || !frame.full {
                    return Err(format!(
                        "first terminal frame must be full sequence 1, got sequence {} full {}",
                        frame.seq, frame.full
                    ));
                }
            }
            Some(last) => {
                let expected = last
                    .checked_add(1)
                    .ok_or_else(|| "terminal frame sequence overflow".to_owned())?;
                if frame.seq != expected {
                    return Err(format!(
                        "terminal frame sequence gap: expected {expected}, got {}",
                        frame.seq
                    ));
                }
            }
        }
        self.last_sequence = Some(frame.seq);
        self.push_event(ClientEvent::Ansi(frame))
    }

    fn queue_outbound(&mut self, message: ClientMessage) -> Result<(), String> {
        self.outbound.push_back(encode_framed(&message)?);
        Ok(())
    }

    fn push_event(&mut self, event: ClientEvent) -> Result<(), String> {
        if self.events.len() >= MAX_QUEUED_EVENTS {
            return Err(format!("event queue exceeds {MAX_QUEUED_EVENTS} entries"));
        }
        let event_bytes = event.data_len();
        if event_bytes > MAX_QUEUED_EVENT_BYTES - self.queued_event_bytes {
            return Err(format!(
                "event queue exceeds {MAX_QUEUED_EVENT_BYTES} bytes"
            ));
        }
        self.queued_event_bytes += event_bytes;
        self.events.push_back(event);
        Ok(())
    }

    fn require_active(&self) -> Result<(), String> {
        match self.state {
            ClientState::Active => Ok(()),
            ClientState::AwaitingWelcome => Err("handshake is not complete".to_owned()),
            ClientState::Closed => Err("client is closed".to_owned()),
            ClientState::Failed => Err("client is failed".to_owned()),
        }
    }

    fn require_not_terminal(&self) -> Result<(), String> {
        match self.state {
            ClientState::AwaitingWelcome | ClientState::Active => Ok(()),
            ClientState::Closed => Err("client is closed".to_owned()),
            ClientState::Failed => Err("client is failed".to_owned()),
        }
    }

    fn fail<T>(&mut self, error: String) -> Result<T, String> {
        self.state = ClientState::Failed;
        self.last_error = Some(error.clone());
        Err(error)
    }
}
