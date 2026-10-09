#ifndef JOURNAL_ARCHIVE_H
#define JOURNAL_ARCHIVE_H
#include <sqlite3.h>
#include <stddef.h>
#include <stdint.h>

/// CRC-32 (IEEE 802.3, as ZIP uses) of `length` bytes, continuing from `crc` (0 to begin), by the system zlib.
uint32_t journal_crc32(uint32_t crc, const uint8_t *bytes, size_t length);

/// Turns SQLite's defensive mode on (1) or off (0) for a connection (sqlite3_db_config is variadic, which Swift cannot
/// call). Returns SQLITE_OK on success. The app only turns it on; tests turn it off to build hostile databases.
int journal_sqlite_set_defensive(sqlite3 *database, int enabled);

/// A raw deflate decoder (the stream ZIP stores, without a zlib header) that reports exactly how many input bytes the
/// stream used: unlike a decoder that buffers its input, it lets a reader refuse bytes after the stream's end.
typedef struct journal_inflater journal_inflater;

journal_inflater *journal_inflater_create(void);
void journal_inflater_destroy(journal_inflater *inflater);

/// Decodes from `input` into `output`. Returns 1 when the stream ended (the bytes it used are in `consumed`),
/// 0 when more input or output room is needed, and -1 when the data is not a valid deflate stream or a length is
/// more than UINT_MAX (zlib counts in unsigned int; nothing is read or written then).
int journal_inflater_step(
    journal_inflater *inflater, const uint8_t *input, size_t input_length, uint8_t *output,
    size_t output_capacity, size_t *consumed, size_t *produced);
#endif
