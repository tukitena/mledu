import type { AvatarContentType } from '@mledu/contracts/profile'

export const AVATAR_EXTENSION: Record<AvatarContentType, 'jpg' | 'png' | 'webp'> = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
}

export const CONTENT_TYPE_OF_EXTENSION: Record<string, AvatarContentType> = {
  jpg: 'image/jpeg',
  png: 'image/png',
  webp: 'image/webp',
}

const startsWith = (bytes: Uint8Array, signature: number[], offset = 0) =>
  bytes.length >= offset + signature.length &&
  signature.every((value, index) => bytes[offset + index] === value)

const ascii = (text: string) => [...text].map((char) => char.charCodeAt(0))

/**
 * Image type from the file's own bytes (AUTH-08), never from the name or the
 * MIME type the browser declared. Returns null for anything else.
 */
export function detectImageType(bytes: Uint8Array): AvatarContentType | null {
  // JPEG: SOI marker followed by another marker, and an EOI marker at the end.
  if (
    startsWith(bytes, [0xff, 0xd8, 0xff]) &&
    bytes.length > 4 &&
    bytes[bytes.length - 2] === 0xff &&
    bytes[bytes.length - 1] === 0xd9
  ) {
    return 'image/jpeg'
  }
  // PNG: 8-byte signature, then the IHDR chunk.
  if (
    startsWith(bytes, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]) &&
    startsWith(bytes, ascii('IHDR'), 12)
  ) {
    return 'image/png'
  }
  // WebP: RIFF container whose declared size matches the file, form type WEBP
  // and a VP8/VP8L/VP8X first chunk.
  if (startsWith(bytes, ascii('RIFF')) && startsWith(bytes, ascii('WEBP'), 8)) {
    const riffSize = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength).getUint32(
      4,
      true,
    )
    const chunk = String.fromCharCode(...bytes.subarray(12, 16))
    if (riffSize + 8 === bytes.length && ['VP8 ', 'VP8L', 'VP8X'].includes(chunk)) {
      return 'image/webp'
    }
  }
  return null
}
