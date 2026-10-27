import { describe, expect, it } from 'vitest'
import { detectImageType } from './image'

const bytes = (...values: number[]) => new Uint8Array(values)
const ascii = (text: string) => [...text].map((char) => char.charCodeAt(0))

describe('detectImageType', () => {
  it('recognizes JPEG by SOI/EOI markers', () => {
    expect(detectImageType(bytes(0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0xff, 0xd9))).toBe(
      'image/jpeg',
    )
    // Truncated JPEG without the end marker.
    expect(detectImageType(bytes(0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10))).toBeNull()
  })

  it('recognizes PNG by signature and IHDR chunk', () => {
    const png = bytes(0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 13, ...ascii('IHDR'))
    expect(detectImageType(png)).toBe('image/png')
    expect(detectImageType(png.subarray(0, 8))).toBeNull()
  })

  it('recognizes WebP only when the RIFF size matches the file', () => {
    const body = [...ascii('WEBP'), ...ascii('VP8L'), 1, 0, 0, 0, 0]
    const size = body.length
    const webp = bytes(...ascii('RIFF'), size, 0, 0, 0, ...body)
    expect(detectImageType(webp)).toBe('image/webp')
    expect(detectImageType(bytes(...ascii('RIFF'), size + 9, 0, 0, 0, ...body))).toBeNull()
    expect(
      detectImageType(bytes(...ascii('RIFF'), 12, 0, 0, 0, ...ascii('WAVEfmt '), 0, 0, 0, 0)),
    ).toBeNull()
  })

  it('rejects text, SVG and empty input whatever the declared type', () => {
    expect(
      detectImageType(new TextEncoder().encode('<svg xmlns="http://www.w3.org/2000/svg"/>')),
    ).toBeNull()
    expect(detectImageType(new Uint8Array())).toBeNull()
  })
})
