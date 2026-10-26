import { createHash } from 'crypto'

export const sha256Hex = (data: Buffer | Uint8Array | string): string =>
  createHash('sha256').update(data).digest('hex')
