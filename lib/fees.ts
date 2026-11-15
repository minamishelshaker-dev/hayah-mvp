// Fee schedule of the pricing model, FIRST RELEASE ONLY: mediation and arbitration, disputes worth 1,500 to 50,000 USD.
// Everything is in US dollars (the platform's standard currency); a payment currency is applied only at display time.
// Negotiation and conciliation (second release) are deliberately absent.
export type Stage = 'mediation' | 'arbitration'
export const BAND = { minUsd: 1500, maxUsd: 50000 } as const
export const inBand = (usd: number) => usd >= BAND.minUsd && usd <= BAND.maxUsd

const r2 = (n: number) => Math.round((n + Number.EPSILON) * 100) / 100
const clamp = (n: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, n))

// Stage fee before any deduction: includes the neutral's fees and the platform's share.
export function nominalFee(stage: Stage, usd: number): number {
  if (stage === 'mediation') {
    if (usd < 5000) return 199
    if (usd < 50000) return r2(clamp(usd * 0.05, 250, 2000))
    return r2(clamp(usd * 0.04, 2000, 4500))
  }
  if (usd < 5000) return 500
  if (usd < 50000) return r2(clamp(usd * 0.12, 600, 5750))
  return r2(clamp(usd * 0.115, 5750, 13500))
}

// The neutral's (mediator's or arbitrator's) share of the nominal fee.
export function neutralPercent(stage: Stage, usd: number): number {
  if (stage === 'mediation') return usd < 25000 ? 0.45 : usd < 50000 ? 0.42 : 0.38
  return usd < 25000 ? 0.62 : usd < 50000 ? 0.60 : 0.58
}

export type StageQuote = {
  stage: Stage; nominal: number; neutral: number; platform: number
  platformCredit: number; platformDue: number; due: number
}

// Moving from an earlier stage: the neutral is paid in full in every stage; only the PLATFORM share is reduced by the platform
// share already collected for the same dispute. (Pricing model, section 4, as amended.)
export function stageDue(stage: Stage, usd: number, platformCredit = 0): StageQuote {
  const nominal = nominalFee(stage, usd)
  const neutral = r2(nominal * neutralPercent(stage, usd))
  const platform = r2(nominal - neutral)                       // rounding differences go to the platform
  const platformDue = r2(Math.max(0, platform - platformCredit))
  return { stage, nominal, neutral, platform, platformCredit, platformDue, due: r2(neutral + platformDue) }
}

export function quotePath(usd: number) {
  const mediation = stageDue('mediation', usd, 0)
  const arbitrationDirect = stageDue('arbitration', usd, 0)
  const arbitrationAfterMediation = stageDue('arbitration', usd, mediation.platformDue)
  return { mediation, arbitrationDirect, arbitrationAfterMediation, totalMediationThenArbitration: r2(mediation.due + arbitrationAfterMediation.due) }
}

export type RateLite = { currency: string; egp_per_unit: number }
const unit = (rates: RateLite[], c: string) => {
  const r = rates.find((x) => x.currency === c)
  if (!r) throw new Error(`no approved rate for ${c}`)
  return Number(r.egp_per_unit)
}
export const toUsd = (amount: number, currency: string, rates: RateLite[]) => r2((amount * unit(rates, currency)) / unit(rates, 'USD'))
export const fromUsd = (usd: number, currency: string, rates: RateLite[]) => r2((usd * unit(rates, 'USD')) / unit(rates, currency))
