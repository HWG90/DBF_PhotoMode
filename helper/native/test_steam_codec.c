/* Standalone codec contracts: fixed MS-XCA vectors, round trips and refusals. */
#include "steam_codec.c"
#include <assert.h>
#include <string.h>

static unsigned char packed[WJL_CODEC_MAX_PACKED], raw[WJL_CODEC_MAX_RAW + 2], source[WJL_CODEC_MAX_RAW];

static void decodes(uint32_t format, const unsigned char *bytes, uint32_t size, const char *expected) {
    uint32_t produced = 99, length = (uint32_t)strlen(expected);
    assert(!wjl_codec_run(WJL_CODEC_DECOMPRESS, format, bytes, size, length, raw, length + 1, &produced));
    assert(produced == length && !memcmp(raw, expected, length));
}

static uint32_t compressed_jobs, incompressible_jobs;
static void round_trip(uint32_t format, uint32_t size, int compressible) {
    uint32_t base = format & ~WJL_CODEC_MAXIMUM, compressed = 0, produced = 0;
    DWORD status = wjl_codec_run(WJL_CODEC_COMPRESS, format, source, size, 0, packed,
                                 wjl_codec_capacity(WJL_CODEC_COMPRESS, size, 0), &compressed);
    if (status == ERROR_NOT_SUPPORTED) return; /* An engine level this Windows build lacks. */
    if (status == WJL_CODEC_INCOMPRESSIBLE) {
        /* Only XPRESS may refuse, and never for large compressible input. */
        assert(base != WJL_CODEC_LZNT1 && compressed == 0 && (!compressible || size < 4096));
        ++incompressible_jobs;
        return;
    }
    ++compressed_jobs;
    assert(!status && compressed > 0 && compressed <= size + size / 8u + 4096u);
    memset(raw, 0xCD, size);
    assert(!wjl_codec_run(WJL_CODEC_DECOMPRESS, base, packed, compressed, size, raw, size + 1, &produced));
    assert(produced == size && !memcmp(raw, source, size));
    /* One byte short or long must be refused, never truncated or padded. */
    if (size < WJL_CODEC_MAX_RAW) {
        assert(wjl_codec_run(WJL_CODEC_DECOMPRESS, base, packed, compressed, size + 1, raw, size + 2, &produced));
        assert(produced == 0);
    }
    if (size > 1) {
        assert(wjl_codec_run(WJL_CODEC_DECOMPRESS, base, packed, compressed, size - 1, raw, size, &produced));
        assert(produced == 0);
    }
}

int main(void) {
    static const unsigned char stored[] = {0x02, 0x30, 'a', 'b', 'c'};
    static const unsigned char repeated[] = {0x03, 0xB0, 0x02, 'a', 0x06, 0x00};
    static const unsigned char xpress[] = {0xFF, 0xFF, 0xFF, 0x1F, 'a', 'b', 'c'};
    static const uint32_t formats[] = {WJL_CODEC_LZNT1, WJL_CODEC_XPRESS, WJL_CODEC_XPRESS_HUFF,
        WJL_CODEC_LZNT1 | WJL_CODEC_MAXIMUM, WJL_CODEC_XPRESS | WJL_CODEC_MAXIMUM,
        WJL_CODEC_XPRESS_HUFF | WJL_CODEC_MAXIMUM};
    static const uint32_t sizes[] = {1, 2, 3, 31, 32, 33, 4095, 4096, 4097, 65536, WJL_CODEC_MAX_RAW};
    uint32_t seed = 0x4C4C4C, produced = 0;

    /* MS-XCA 2.5: an uncompressed LZNT1 chunk and a one-literal, one-match chunk. */
    decodes(WJL_CODEC_LZNT1, stored, sizeof(stored), "abc");
    decodes(WJL_CODEC_LZNT1, repeated, sizeof(repeated), "aaaaaaaaaa");
    /* MS-XCA 2.4: plain XPRESS literals followed by end-of-input flag bits. */
    decodes(WJL_CODEC_XPRESS, xpress, sizeof(xpress), "abc");

    for (uint32_t pattern = 0; pattern < 3; ++pattern) {
        for (uint32_t index = 0; index < WJL_CODEC_MAX_RAW; ++index) {
            seed = seed * 1664525u + 1013904223u;
            source[index] = pattern == 0 ? 0 : pattern == 1 ? (unsigned char)(seed >> 24)
                                                          : (unsigned char)("LiveLuaLoader "[index % 14] ^ (index / 997));
        }
        for (size_t f = 0; f < sizeof(formats) / sizeof(*formats); ++f)
            for (size_t s = 0; s < sizeof(sizes) / sizeof(*sizes); ++s) round_trip(formats[f], sizes[s], pattern != 1);
    }

    assert(compressed_jobs >= 120 && incompressible_jobs > 0);

    /* Refusals: unknown format/mode, empty or oversized input, a maximum flag
     * on decompression, a short output buffer and corrupt compressed data. */
    assert(wjl_codec_run(WJL_CODEC_COMPRESS, 5, source, 16, 0, packed, 8192, &produced) == ERROR_NOT_SUPPORTED);
    assert(wjl_codec_run(WJL_CODEC_COMPRESS, 0, source, 16, 0, packed, 8192, &produced) == ERROR_NOT_SUPPORTED);
    assert(wjl_codec_run(2, WJL_CODEC_LZNT1, source, 16, 0, packed, 8192, &produced) == ERROR_INVALID_PARAMETER);
    assert(wjl_codec_run(WJL_CODEC_COMPRESS, WJL_CODEC_LZNT1, source, 0, 0, packed, 8192, &produced) == ERROR_INVALID_PARAMETER);
    assert(wjl_codec_run(WJL_CODEC_COMPRESS, WJL_CODEC_LZNT1, source, WJL_CODEC_MAX_RAW + 1, 0, packed,
                         WJL_CODEC_MAX_PACKED, &produced) == ERROR_INVALID_PARAMETER);
    assert(wjl_codec_run(WJL_CODEC_COMPRESS, WJL_CODEC_LZNT1, source, 16, 1, packed, 8192, &produced) == ERROR_INVALID_PARAMETER);
    assert(wjl_codec_run(WJL_CODEC_COMPRESS, WJL_CODEC_LZNT1, source, 4096, 0, packed, 4096, &produced) == ERROR_INSUFFICIENT_BUFFER);
    assert(wjl_codec_run(WJL_CODEC_DECOMPRESS, WJL_CODEC_LZNT1 | WJL_CODEC_MAXIMUM, stored, sizeof(stored), 3,
                         raw, 4, &produced) == ERROR_INVALID_PARAMETER);
    assert(wjl_codec_run(WJL_CODEC_DECOMPRESS, WJL_CODEC_LZNT1, stored, sizeof(stored), 0, raw, 4, &produced) == ERROR_INVALID_PARAMETER);
    assert(wjl_codec_run(WJL_CODEC_DECOMPRESS, WJL_CODEC_LZNT1, stored, sizeof(stored), WJL_CODEC_MAX_RAW + 1,
                         raw, WJL_CODEC_MAX_RAW + 2, &produced) == ERROR_INVALID_PARAMETER);
    assert(wjl_codec_run(WJL_CODEC_DECOMPRESS, WJL_CODEC_LZNT1, stored, sizeof(stored), 3, raw, 3, &produced) == ERROR_INSUFFICIENT_BUFFER);
    assert(wjl_codec_run(WJL_CODEC_DECOMPRESS, WJL_CODEC_LZNT1, stored, sizeof(stored), 2, raw, 3, &produced));
    {
        static const unsigned char corrupt[] = {0x03, 0xB0, 0x02, 'a', 0x06, 0x10};
        assert(wjl_codec_run(WJL_CODEC_DECOMPRESS, WJL_CODEC_LZNT1, corrupt, sizeof(corrupt), 10, raw, 11, &produced));
        assert(produced == 0);
    }
    return 0;
}
