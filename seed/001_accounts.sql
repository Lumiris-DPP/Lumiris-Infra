BEGIN;

CREATE TABLE IF NOT EXISTS _seed_audit (
    filename   TEXT PRIMARY KEY,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TEMP TABLE created_accounts (email TEXT) ON COMMIT DROP;

WITH inserted AS (
    INSERT INTO users (email, password_hash, role, name, is_verified)
    VALUES
        (lower(:'admin_email'),    crypt(:'admin_password',    gen_salt('bf', 10)), 'ADMIN',    :'admin_name',    true),
        (lower(:'repairer_email'), crypt(:'repairer_password', gen_salt('bf', 10)), 'REPAIRER', :'repairer_name', true),
        (lower(:'artisan_email'),  crypt(:'artisan_password',  gen_salt('bf', 10)), 'ARTISAN',  :'artisan_name',  true),
        (lower(:'consumer_email'), crypt(:'consumer_password', gen_salt('bf', 10)), 'CONSUMER', :'consumer_name', true)
    ON CONFLICT (email) DO NOTHING
    RETURNING email
)
INSERT INTO created_accounts (email)
SELECT email FROM inserted;

INSERT INTO artisan_profiles (user_id, display_name, atelier_name, slug, city, region, tier, passport_limit,
                              status, siret, company_name, naf_code,
                              declaration_signed, signature_timestamp, joined_at)
SELECT id, :'artisan_name', :'artisan_atelier', :'artisan_slug', :'artisan_city', :'artisan_region', 'Solo', 50,
       'VERIFIED', :'artisan_siret', :'artisan_company', :'artisan_naf',
       true, NOW(), NOW()
FROM users
WHERE email = lower(:'artisan_email')
ON CONFLICT (user_id) DO UPDATE SET
    status              = EXCLUDED.status,
    siret               = EXCLUDED.siret,
    company_name        = EXCLUDED.company_name,
    naf_code            = EXCLUDED.naf_code,
    declaration_signed  = EXCLUDED.declaration_signed,
    signature_timestamp = COALESCE(artisan_profiles.signature_timestamp, EXCLUDED.signature_timestamp);

INSERT INTO _seed_audit (filename) VALUES ('001_accounts.sql')
ON CONFLICT (filename) DO NOTHING;

SELECT email FROM created_accounts;

COMMIT;
