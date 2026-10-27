// Letters and digits without look-alikes (0/O, 1/l/I), so an Admin can read the
// password out to the user (AUTH-02 "giao qua kênh sẵn có").
const ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789'
const LENGTH = 12

/** Random temporary password; shown to the Admin once and never stored readable. */
export function generateTemporaryPassword(): string {
  // Rejection sampling keeps every character equally likely.
  const limit = 256 - (256 % ALPHABET.length)
  let result = ''
  while (result.length < LENGTH) {
    for (const byte of crypto.getRandomValues(new Uint8Array(LENGTH * 2))) {
      if (byte < limit && result.length < LENGTH) result += ALPHABET[byte % ALPHABET.length]
    }
  }
  return result
}
