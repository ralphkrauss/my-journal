#ifndef JOURNAL_CRYPTO_H
#define JOURNAL_CRYPTO_H
#include <stddef.h>
#include <stdint.h>
int journal_pbkdf2(const char *password, size_t password_length, const uint8_t *salt, size_t salt_length, uint32_t iterations, uint8_t *output, size_t output_length);
#endif
