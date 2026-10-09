#include "JournalArchive.h"
#include <stdlib.h>
#include <zlib.h>

uint32_t journal_crc32(uint32_t crc, const uint8_t *bytes, size_t length) {
    uLong value = crc;
    while (length > 0) {
        uInt chunk = length > 0x40000000 ? 0x40000000 : (uInt)length;
        value = crc32(value, bytes, chunk);
        bytes += chunk;
        length -= chunk;
    }
    return (uint32_t)value;
}

int journal_sqlite_enable_defensive(sqlite3 *database) {
    int enabled = 0;
    return sqlite3_db_config(database, SQLITE_DBCONFIG_DEFENSIVE, 1, &enabled);
}

struct journal_inflater {
    z_stream stream;
};

journal_inflater *journal_inflater_create(void) {
    journal_inflater *inflater = calloc(1, sizeof(journal_inflater));
    if (inflater == NULL) {
        return NULL;
    }
    if (inflateInit2(&inflater->stream, -15) != Z_OK) {
        free(inflater);
        return NULL;
    }
    return inflater;
}

void journal_inflater_destroy(journal_inflater *inflater) {
    if (inflater != NULL) {
        inflateEnd(&inflater->stream);
        free(inflater);
    }
}

int journal_inflater_step(
    journal_inflater *inflater, const uint8_t *input, size_t input_length, uint8_t *output,
    size_t output_capacity, size_t *consumed, size_t *produced) {
    z_stream *stream = &inflater->stream;
    stream->next_in = (Bytef *)input;
    stream->avail_in = (uInt)input_length;
    stream->next_out = output;
    stream->avail_out = (uInt)output_capacity;
    int status = inflate(stream, Z_NO_FLUSH);
    *consumed = input_length - stream->avail_in;
    *produced = output_capacity - stream->avail_out;
    if (status == Z_STREAM_END) {
        return 1;
    }
    if (status == Z_OK || status == Z_BUF_ERROR) {
        return 0;
    }
    return -1;
}
