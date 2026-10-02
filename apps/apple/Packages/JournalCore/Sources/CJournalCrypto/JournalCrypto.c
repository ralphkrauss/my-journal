#include "JournalCrypto.h"
#include <CommonCrypto/CommonKeyDerivation.h>
int journal_pbkdf2(const char *password, size_t password_length, const uint8_t *salt, size_t salt_length, uint32_t iterations, uint8_t *output, size_t output_length) {
    return CCKeyDerivationPBKDF(kCCPBKDF2, password, password_length, salt, salt_length, kCCPRFHmacAlgSHA256, iterations, output, output_length);
}
