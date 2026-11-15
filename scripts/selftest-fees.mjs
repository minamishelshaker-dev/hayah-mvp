// Unit test for lib/fees.ts against the worked examples of the pricing model.   npm run test:fees   (Node 22+)
import { nominalFee, neutralPercent, stageDue, quotePath, inBand, toUsd, fromUsd } from '../lib/fees.ts'
let failed = 0
const check = (cond, msg) => { if (!cond) { failed++; console.error('FAIL:', msg) } }
const eq = (a, b, msg) => check(Math.abs(a - b) < 0.005, `${msg}: got ${a}, expected ${b}`)

// the document's table "direct entry to ordinary arbitration" (platform and arbitrator shares)
for (const [usd, fee, arb, plat] of [[10000, 1200, 744, 456], [25000, 3000, 1800, 1200], [50000, 5750, 3335, 2415]]) {
  const q = stageDue('arbitration', usd)
  eq(q.nominal, fee, `arbitration fee at ${usd}`); eq(q.neutral, arb, `arbitrator share at ${usd}`); eq(q.platform, plat, `platform share at ${usd}`)
}
eq(nominalFee('arbitration', 2000), 500, 'fixed arbitration fee below 5,000'); eq(nominalFee('mediation', 2000), 199, 'fixed mediation fee below 5,000')
eq(nominalFee('mediation', 5000), 250, 'mediation minimum at 5,000'); eq(nominalFee('mediation', 10000), 500, 'mediation 5% at 10,000')
eq(nominalFee('mediation', 40000), 2000, 'mediation cap'); eq(nominalFee('mediation', 49999), 2000, 'mediation cap just below 50,000')
eq(nominalFee('arbitration', 5000), 600, 'arbitration minimum at 5,000'); eq(nominalFee('arbitration', 49999), 5750, 'arbitration cap just below 50,000')
eq(neutralPercent('mediation', 10000), 0.45, 'mediator share below 25,000'); eq(neutralPercent('arbitration', 30000), 0.60, 'arbitrator share 25,000 to 50,000')

// the neutral is paid in full in every stage; only the platform share is credited (mediation then arbitration at 40,000)
const p = quotePath(40000)
eq(p.mediation.nominal, 2000, 'mediation at 40,000'); eq(p.mediation.neutral, 840, 'mediator'); eq(p.mediation.platform, 1160, 'platform in mediation'); eq(p.mediation.due, 2000, 'mediation due')
eq(p.arbitrationDirect.nominal, 4800, 'arbitration at 40,000'); eq(p.arbitrationDirect.neutral, 2880, 'arbitrator'); eq(p.arbitrationDirect.platform, 1920, 'platform in arbitration')
eq(p.arbitrationAfterMediation.platformDue, 760, 'platform share after the credit'); eq(p.arbitrationAfterMediation.due, 3640, 'arbitration due after mediation')
eq(p.totalMediationThenArbitration, 5640, 'total = neutrals in full (840 + 2,880) + the platform share of the last stage (1,920)')
check(p.arbitrationAfterMediation.neutral === p.arbitrationDirect.neutral, 'the arbitrator gets the same fee whether or not a mediation came first')
check(p.arbitrationAfterMediation.due >= p.arbitrationAfterMediation.neutral, 'the amount due never falls below the neutral\'s fee')
// a credit larger than the platform share leaves the neutral's fee untouched
eq(stageDue('arbitration', 10000, 99999).due, 744, 'a huge credit still leaves the arbitrator paid in full')

// band and conversion
check(inBand(1500) && inBand(50000) && !inBand(1499.99) && !inBand(50000.01), 'band limits are inclusive: 1,500 to 50,000 USD')
const rates = [{ currency: 'EGP', egp_per_unit: 1 }, { currency: 'USD', egp_per_unit: 53.435 }, { currency: 'EUR', egp_per_unit: 59.26475 }]
eq(toUsd(53435, 'EGP', rates), 1000, 'EGP to USD'); eq(toUsd(1000, 'USD', rates), 1000, 'USD to USD'); eq(fromUsd(1000, 'EGP', rates), 53435, 'USD to EGP')
eq(toUsd(1000, 'EUR', rates), 1109.1, 'EUR to USD'); eq(fromUsd(1109.1, 'EUR', rates), 1000, 'USD to EUR')
let threw = false; try { toUsd(1, 'JPY', rates) } catch { threw = true }; check(threw, 'an unsupported currency throws')
if (failed) { console.error(failed + ' check(s) failed'); process.exit(1) }
console.log('fees self-test: all checks passed')
