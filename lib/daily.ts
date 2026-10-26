const API = 'https://api.daily.co/v1'

export const dailyEnabled = () => Boolean(process.env.DAILY_API_KEY)

const headers = () => ({
  'Content-Type': 'application/json',
  Authorization: `Bearer ${process.env.DAILY_API_KEY}`,
})

// Private room. Recording is OFF: mediation is confidential and recording needs explicit consent.
export async function createRoom(name: string, expiresInSec: number) {
  const res = await fetch(`${API}/rooms`, {
    method: 'POST',
    headers: headers(),
    body: JSON.stringify({
      name,
      privacy: 'private',
      properties: {
        max_participants: 6,
        enable_chat: true,
        enable_screenshare: true,
        exp: Math.floor(Date.now() / 1000) + expiresInSec,
        eject_at_room_exp: true,
      },
    }),
  })
  if (!res.ok) throw new Error(`Daily room error: ${res.status}`)
  return (await res.json()) as { name: string; url: string }
}

// A private room can only be joined with a meeting token.
export async function createMeetingToken(roomName: string, userName: string, isOwner: boolean, expiresInSec: number, notBeforeEpoch?: number) {
  const res = await fetch(`${API}/meeting-tokens`, {
    method: 'POST',
    headers: headers(),
    body: JSON.stringify({
      properties: {
        room_name: roomName,
        user_name: userName,
        is_owner: isOwner,
        exp: Math.floor(Date.now() / 1000) + expiresInSec,
        ...(notBeforeEpoch ? { nbf: notBeforeEpoch } : {}),
      },
    }),
  })
  if (!res.ok) throw new Error(`Daily token error: ${res.status}`)
  return ((await res.json()) as { token: string }).token
}
