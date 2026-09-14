import http from 'k6/http';
import { check } from 'k6';

const BASE = __ENV.BASE || 'http://localhost:8080';
// Public code of a seeded/published DPP — pass one that exists on the target env.
const PUBLIC_CODE = __ENV.PUBLIC_CODE || 'DEMO0001';

export const options = {
    scenarios: {
        scan_burst: {
            executor: 'ramping-arrival-rate',
            startRate: 20,
            timeUnit: '1s',
            preAllocatedVUs: 30,
            maxVUs: 200,
            stages: [
                { duration: '30s', target: 50 },
                { duration: '1m', target: 200 },
                { duration: '1m', target: 400 },
                { duration: '30s', target: 0 },
            ],
        },
    },
    thresholds: {
        http_req_failed: ['rate<0.005'],
        // SLO ticket : p95 du lookup passeport < 80ms.
        http_req_duration: ['p(95)<80'],
        checks: ['rate>0.999'],
    },
};

export default function () {
    const res = http.get(`${BASE}/public/dpp_forms/${PUBLIC_CODE}`);

    check(res, {
        '200 OK': (r) => r.status === 200,
        'has publicCode': (r) => {
            try {
                return r.json('publicCode') === PUBLIC_CODE;
            } catch {
                return false;
            }
        },
    });
}

export function handleSummary(data) {
    return {
        'bench/out/passport-lookup.json': JSON.stringify(data, null, 2),
        stdout: textSummary(data),
    };
}

function textSummary(data) {
    const m = data.metrics;
    const p95 = m.http_req_duration?.values?.['p(95)']?.toFixed(1) ?? 'n/a';
    const fail = m.http_req_failed?.values?.rate?.toFixed(4) ?? 'n/a';
    return `\n[passport-lookup] p95=${p95}ms · failure_rate=${fail} (SLO: p95<80ms)\n`;
}
