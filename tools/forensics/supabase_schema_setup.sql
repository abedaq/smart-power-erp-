-- ========================================================
-- SmartPower ERP: Remote Cloud Backup & Signed Patch Schema
-- Run this script once in Supabase SQL Editor
-- ========================================================

-- 1. Create Storage Bucket for Station Backups (if not exists)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'station-backups',
    'station-backups',
    true,
    524288000, -- 500 MB limit
    ARRAY['application/gzip', 'application/octet-stream', 'application/x-gzip']
)
ON CONFLICT (id) DO UPDATE SET
    public = true,
    file_size_limit = 524288000;

-- Allow anon upload and read for station-backups bucket
CREATE POLICY "Allow anon upload to station-backups"
ON storage.objects FOR INSERT
TO anon
WITH CHECK (bucket_id = 'station-backups');

CREATE POLICY "Allow anon select from station-backups"
ON storage.objects FOR SELECT
TO anon
USING (bucket_id = 'station-backups');

CREATE POLICY "Allow anon update to station-backups"
ON storage.objects FOR UPDATE
TO anon
USING (bucket_id = 'station-backups');

-- 2. Verified Station Backups Table
CREATE TABLE IF NOT EXISTS public.station_database_backups (
    id BIGSERIAL PRIMARY KEY,
    reference_id TEXT NOT NULL UNIQUE,
    license_key TEXT,
    hwid TEXT NOT NULL,
    station_name TEXT,
    app_version TEXT NOT NULL,
    file_name TEXT NOT NULL,
    file_url TEXT NOT NULL,
    file_size_bytes BIGINT NOT NULL,
    sha256_hash TEXT NOT NULL,
    customer_count INT DEFAULT 0,
    last_invoice_id BIGINT,
    last_payment_id BIGINT,
    user_note TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_station_backups_hwid 
ON public.station_database_backups(hwid, created_at DESC);

-- Enable RLS and grant access for station_database_backups
ALTER TABLE public.station_database_backups ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow anon read/write on station_database_backups"
ON public.station_database_backups FOR ALL
TO anon
USING (true)
WITH CHECK (true);

-- 3. Targeted & Signed Remote Commands Table
CREATE TABLE IF NOT EXISTS public.station_remote_commands (
    id BIGSERIAL PRIMARY KEY,
    target_hwid TEXT NOT NULL,
    target_license_key TEXT,
    command_type TEXT NOT NULL,                 -- 'FORCE_BACKUP', 'RUN_SQL_PATCH', 'GET_DIAGNOSTICS'
    min_app_version TEXT,
    max_app_version TEXT,
    payload JSONB NOT NULL DEFAULT '{}'::jsonb, -- { "sql": "...", "transactional": true }
    signature TEXT NOT NULL,                    -- Ed25519 canonical signature
    status TEXT DEFAULT 'PENDING',              -- PENDING, PROCESSING, COMPLETED, FAILED, EXPIRED, SKIPPED
    result_output TEXT,
    error_message TEXT,
    affected_rows INT DEFAULT 0,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    started_at TIMESTAMPTZ,
    executed_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_station_commands_lookup 
ON public.station_remote_commands(target_hwid, status, created_at ASC);

-- Enable RLS and grant access for station_remote_commands
ALTER TABLE public.station_remote_commands ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow anon read/write on station_remote_commands"
ON public.station_remote_commands FOR ALL
TO anon
USING (true)
WITH CHECK (true);

-- 4. Atomic Claim Function (FOR UPDATE SKIP LOCKED)
CREATE OR REPLACE FUNCTION public.claim_next_station_command(
    p_hwid TEXT,
    p_app_version TEXT
)
RETURNS TABLE (
    command_id BIGINT,
    cmd_type TEXT,
    cmd_payload JSONB,
    cmd_signature TEXT,
    cmd_min_version TEXT,
    cmd_max_version TEXT
) 
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_rec RECORD;
BEGIN
    -- Expire stale pending commands past TTL
    UPDATE public.station_remote_commands
    SET status = 'EXPIRED', executed_at = NOW()
    WHERE status = 'PENDING' 
      AND expires_at IS NOT NULL 
      AND expires_at < NOW();

    -- Atomically lock and claim the oldest pending command for this specific station
    SELECT id, command_type, payload, signature, min_app_version, max_app_version
    INTO v_rec
    FROM public.station_remote_commands
    WHERE target_hwid = p_hwid
      AND status = 'PENDING'
    ORDER BY created_at ASC
    LIMIT 1
    FOR UPDATE SKIP LOCKED;

    IF v_rec.id IS NOT NULL THEN
        UPDATE public.station_remote_commands
        SET status = 'PROCESSING', started_at = NOW()
        WHERE id = v_rec.id;

        RETURN QUERY SELECT 
            v_rec.id, 
            v_rec.command_type, 
            v_rec.payload, 
            v_rec.signature, 
            v_rec.min_app_version, 
            v_rec.max_app_version;
    END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.claim_next_station_command(TEXT, TEXT) TO anon;
GRANT EXECUTE ON FUNCTION public.claim_next_station_command(TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.claim_next_station_command(TEXT, TEXT) TO service_role;
