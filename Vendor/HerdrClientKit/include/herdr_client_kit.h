#ifndef HERDR_CLIENT_KIT_H
#define HERDR_CLIENT_KIT_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif
typedef struct HerdrClientCore herdr_client_t;

typedef struct herdr_buffer {
    uint8_t *ptr;
    size_t len;
    size_t capacity;
} herdr_buffer_t;

typedef struct herdr_event {
    uint32_t kind;
    uint64_t sequence;
    uint16_t width;
    uint16_t height;
    uint8_t full;
    herdr_buffer_t data;
} herdr_event_t;

enum {
    HERDR_STATUS_OK = 0,
    HERDR_STATUS_EMPTY = 1,
    HERDR_STATUS_INVALID_ARGUMENT = -1,
    HERDR_STATUS_ERROR = -2,
    HERDR_STATUS_PANIC = -128,
};

enum {
    HERDR_EVENT_WELCOME = 1,
    HERDR_EVENT_ANSI = 2,
    HERDR_EVENT_GRAPHICS = 3,
    HERDR_EVENT_SHUTDOWN = 4,
};

enum {
    HERDR_SCROLL_UP = 0,
    HERDR_SCROLL_DOWN = 1,
};

uint32_t herdr_client_protocol_version(void);

/* Returns NULL when dimensions are invalid or allocation panics. */
herdr_client_t *herdr_client_new(uint16_t cols, uint16_t rows);
void herdr_client_free(herdr_client_t *client);

int32_t herdr_client_feed(herdr_client_t *client, const uint8_t *bytes, size_t length);
int32_t herdr_client_send_input(herdr_client_t *client, const uint8_t *bytes, size_t length);
int32_t herdr_client_resize(herdr_client_t *client, uint16_t cols, uint16_t rows);
int32_t herdr_client_scroll(herdr_client_t *client, uint32_t direction, uint16_t lines);
int32_t herdr_client_detach(herdr_client_t *client);

/*
 * Successful take functions transfer one Rust allocation to the caller.
 * Always release returned buffers with herdr_buffer_free, and events with
 * herdr_event_free. EMPTY leaves output initialized to zero.
 */
int32_t herdr_client_take_outbound(herdr_client_t *client, herdr_buffer_t *output);
int32_t herdr_client_next_event(herdr_client_t *client, herdr_event_t *output);
int32_t herdr_client_take_error(herdr_client_t *client, herdr_buffer_t *output);
void herdr_buffer_free(herdr_buffer_t *buffer);
void herdr_event_free(herdr_event_t *event);

#ifdef __cplusplus
}
#endif

#endif
