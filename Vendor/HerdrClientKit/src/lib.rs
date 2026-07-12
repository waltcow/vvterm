mod core;
mod protocol;

use std::panic::{catch_unwind, AssertUnwindSafe};
use std::ptr;
use std::slice;

use crate::core::{ClientEvent, HerdrClientCore};
use crate::protocol::PROTOCOL_VERSION;

pub const HERDR_STATUS_OK: i32 = 0;
pub const HERDR_STATUS_EMPTY: i32 = 1;
pub const HERDR_STATUS_INVALID_ARGUMENT: i32 = -1;
pub const HERDR_STATUS_ERROR: i32 = -2;
pub const HERDR_STATUS_PANIC: i32 = -128;

pub const HERDR_EVENT_WELCOME: u32 = 1;
pub const HERDR_EVENT_ANSI: u32 = 2;
pub const HERDR_EVENT_GRAPHICS: u32 = 3;
pub const HERDR_EVENT_SHUTDOWN: u32 = 4;

#[repr(C)]
#[derive(Debug)]
pub struct HerdrBuffer {
    pub ptr: *mut u8,
    pub len: usize,
    pub capacity: usize,
}

impl HerdrBuffer {
    fn from_vec(mut bytes: Vec<u8>) -> Self {
        if bytes.is_empty() {
            return Self::default();
        }
        let buffer = Self {
            ptr: bytes.as_mut_ptr(),
            len: bytes.len(),
            capacity: bytes.capacity(),
        };
        std::mem::forget(bytes);
        buffer
    }
}

impl Default for HerdrBuffer {
    fn default() -> Self {
        Self {
            ptr: ptr::null_mut(),
            len: 0,
            capacity: 0,
        }
    }
}

#[repr(C)]
#[derive(Debug, Default)]
pub struct HerdrEvent {
    pub kind: u32,
    pub sequence: u64,
    pub width: u16,
    pub height: u16,
    pub full: u8,
    pub data: HerdrBuffer,
}

impl HerdrEvent {
    fn from_core(event: ClientEvent) -> Self {
        match event {
            ClientEvent::Welcome { version } => Self {
                kind: HERDR_EVENT_WELCOME,
                sequence: u64::from(version),
                ..Self::default()
            },
            ClientEvent::Ansi(frame) => Self {
                kind: HERDR_EVENT_ANSI,
                sequence: frame.seq,
                width: frame.width,
                height: frame.height,
                full: u8::from(frame.full),
                data: HerdrBuffer::from_vec(frame.bytes),
            },
            ClientEvent::Graphics(bytes) => Self {
                kind: HERDR_EVENT_GRAPHICS,
                data: HerdrBuffer::from_vec(bytes),
                ..Self::default()
            },
            ClientEvent::Shutdown { reason } => Self {
                kind: HERDR_EVENT_SHUTDOWN,
                data: HerdrBuffer::from_vec(reason.unwrap_or_default().into_bytes()),
                ..Self::default()
            },
        }
    }
}

#[no_mangle]
pub extern "C" fn herdr_client_protocol_version() -> u32 {
    PROTOCOL_VERSION
}

#[no_mangle]
pub extern "C" fn herdr_client_new(cols: u16, rows: u16) -> *mut HerdrClientCore {
    match catch_unwind(AssertUnwindSafe(|| HerdrClientCore::new(cols, rows))) {
        Ok(Ok(client)) => Box::into_raw(Box::new(client)),
        Ok(Err(_)) | Err(_) => ptr::null_mut(),
    }
}

#[no_mangle]
/// # Safety
/// `client` must be null or a live pointer returned by `herdr_client_new` that has not been freed.
pub unsafe extern "C" fn herdr_client_free(client: *mut HerdrClientCore) {
    if client.is_null() {
        return;
    }
    let _ = catch_unwind(AssertUnwindSafe(|| {
        drop(Box::from_raw(client));
    }));
}

#[no_mangle]
/// # Safety
/// `client` must be live. When `length > 0`, `bytes` must reference `length` readable bytes.
pub unsafe extern "C" fn herdr_client_feed(
    client: *mut HerdrClientCore,
    bytes: *const u8,
    length: usize,
) -> i32 {
    if length > 0 && bytes.is_null() {
        return record_argument_error(client, "feed bytes pointer is null");
    }
    with_client(client, |client| {
        let bytes = if length == 0 {
            &[]
        } else {
            slice::from_raw_parts(bytes, length)
        };
        client.feed(bytes)
    })
}

#[no_mangle]
/// # Safety
/// `client` must be live. When `length > 0`, `bytes` must reference `length` readable bytes.
pub unsafe extern "C" fn herdr_client_send_input(
    client: *mut HerdrClientCore,
    bytes: *const u8,
    length: usize,
) -> i32 {
    if length > 0 && bytes.is_null() {
        return record_argument_error(client, "input bytes pointer is null");
    }
    with_client(client, |client| {
        let bytes = if length == 0 {
            &[]
        } else {
            slice::from_raw_parts(bytes, length)
        };
        client.send_input(bytes)
    })
}

#[no_mangle]
/// # Safety
/// `client` must be a live pointer returned by `herdr_client_new`.
pub unsafe extern "C" fn herdr_client_resize(
    client: *mut HerdrClientCore,
    cols: u16,
    rows: u16,
) -> i32 {
    with_client(client, |client| client.resize(cols, rows))
}

#[no_mangle]
/// # Safety
/// `client` must be a live pointer returned by `herdr_client_new`.
pub unsafe extern "C" fn herdr_client_detach(client: *mut HerdrClientCore) -> i32 {
    with_client(client, HerdrClientCore::detach)
}

#[no_mangle]
/// # Safety
/// `client` must be live and `output` must reference writable storage. Any returned buffer must
/// later be passed to `herdr_buffer_free` exactly once.
pub unsafe extern "C" fn herdr_client_take_outbound(
    client: *mut HerdrClientCore,
    output: *mut HerdrBuffer,
) -> i32 {
    if output.is_null() {
        return record_argument_error(client, "outbound output pointer is null");
    }
    if client.is_null() {
        return HERDR_STATUS_INVALID_ARGUMENT;
    }
    match catch_unwind(AssertUnwindSafe(|| {
        *output = HerdrBuffer::default();
        match (&mut *client).take_outbound() {
            Some(bytes) => {
                *output = HerdrBuffer::from_vec(bytes);
                HERDR_STATUS_OK
            }
            None => HERDR_STATUS_EMPTY,
        }
    })) {
        Ok(status) => status,
        Err(_) => {
            (&mut *client).record_ffi_error("panic while taking outbound bytes".to_owned());
            HERDR_STATUS_PANIC
        }
    }
}

#[no_mangle]
/// # Safety
/// `client` must be live and `output` must reference writable storage. Any returned event must
/// later be passed to `herdr_event_free` exactly once.
pub unsafe extern "C" fn herdr_client_next_event(
    client: *mut HerdrClientCore,
    output: *mut HerdrEvent,
) -> i32 {
    if output.is_null() {
        return record_argument_error(client, "event output pointer is null");
    }
    if client.is_null() {
        return HERDR_STATUS_INVALID_ARGUMENT;
    }
    match catch_unwind(AssertUnwindSafe(|| {
        *output = HerdrEvent::default();
        match (&mut *client).next_event() {
            Some(event) => {
                *output = HerdrEvent::from_core(event);
                HERDR_STATUS_OK
            }
            None => HERDR_STATUS_EMPTY,
        }
    })) {
        Ok(status) => status,
        Err(_) => {
            (&mut *client).record_ffi_error("panic while taking client event".to_owned());
            HERDR_STATUS_PANIC
        }
    }
}

#[no_mangle]
/// # Safety
/// `client` must be live and `output` must reference writable storage. Any returned buffer must
/// later be passed to `herdr_buffer_free` exactly once.
pub unsafe extern "C" fn herdr_client_take_error(
    client: *mut HerdrClientCore,
    output: *mut HerdrBuffer,
) -> i32 {
    if client.is_null() || output.is_null() {
        return HERDR_STATUS_INVALID_ARGUMENT;
    }
    match catch_unwind(AssertUnwindSafe(|| {
        *output = HerdrBuffer::default();
        match (&mut *client).take_error() {
            Some(error) => {
                *output = HerdrBuffer::from_vec(error.into_bytes());
                HERDR_STATUS_OK
            }
            None => HERDR_STATUS_EMPTY,
        }
    })) {
        Ok(status) => status,
        Err(_) => HERDR_STATUS_PANIC,
    }
}

#[no_mangle]
/// # Safety
/// `buffer` must be null or reference a buffer initialized by this library. Owned data may be
/// released exactly once.
pub unsafe extern "C" fn herdr_buffer_free(buffer: *mut HerdrBuffer) {
    if buffer.is_null() {
        return;
    }
    let _ = catch_unwind(AssertUnwindSafe(|| {
        let buffer = &mut *buffer;
        if !buffer.ptr.is_null() {
            drop(Vec::from_raw_parts(buffer.ptr, buffer.len, buffer.capacity));
        }
        *buffer = HerdrBuffer::default();
    }));
}

#[no_mangle]
/// # Safety
/// `event` must be null or reference an event initialized by this library. Owned data may be
/// released exactly once.
pub unsafe extern "C" fn herdr_event_free(event: *mut HerdrEvent) {
    if event.is_null() {
        return;
    }
    let _ = catch_unwind(AssertUnwindSafe(|| {
        herdr_buffer_free(&mut (*event).data);
        *event = HerdrEvent::default();
    }));
}

unsafe fn with_client(
    client: *mut HerdrClientCore,
    operation: impl FnOnce(&mut HerdrClientCore) -> Result<(), String>,
) -> i32 {
    if client.is_null() {
        return HERDR_STATUS_INVALID_ARGUMENT;
    }
    match catch_unwind(AssertUnwindSafe(|| operation(&mut *client))) {
        Ok(Ok(())) => HERDR_STATUS_OK,
        Ok(Err(error)) => {
            (&mut *client).record_ffi_error(error);
            HERDR_STATUS_ERROR
        }
        Err(_) => {
            (&mut *client).record_ffi_error("panic inside HerdrClientKit".to_owned());
            HERDR_STATUS_PANIC
        }
    }
}

unsafe fn record_argument_error(client: *mut HerdrClientCore, message: &str) -> i32 {
    if !client.is_null() {
        (&mut *client).record_ffi_error(message.to_owned());
    }
    HERDR_STATUS_INVALID_ARGUMENT
}

#[cfg(test)]
mod tests;
