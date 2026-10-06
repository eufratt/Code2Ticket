-- ==============================================================================
-- Code2Ticket - Database Schema
-- Supabase PostgreSQL (Used purely as an online database)
-- ==============================================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ------------------------------------------------------------------------------
-- 1. USERS & SESSIONS (Custom Auth - No Third Party Auth Service)
-- ------------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash VARCHAR(64) UNIQUE NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    revoked BOOLEAN NOT NULL DEFAULT false
);

CREATE INDEX IF NOT EXISTS idx_sessions_token_hash ON sessions(token_hash);
CREATE INDEX IF NOT EXISTS idx_sessions_user_id ON sessions(user_id);

-- ------------------------------------------------------------------------------
-- 2. GIVEAWAYS & CAMPAIGNS
-- ------------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS giveaways (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title VARCHAR(255) NOT NULL,
    category VARCHAR(50) NOT NULL,
    prize_name VARCHAR(255) NOT NULL,
    prize_value_usd NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    description TEXT,
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    radius_km DOUBLE PRECISION DEFAULT 10.0,
    geo_restricted BOOLEAN NOT NULL DEFAULT false,
    start_at TIMESTAMPTZ NOT NULL,
    end_at TIMESTAMPTZ NOT NULL,
    draw_at TIMESTAMPTZ NOT NULL,
    winner_count INT NOT NULL DEFAULT 1,
    status VARCHAR(30) NOT NULL DEFAULT 'active' CHECK (status IN ('upcoming', 'active', 'drawing', 'completed', 'cancelled')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_giveaways_status ON giveaways(status);
CREATE INDEX IF NOT EXISTS idx_giveaways_category ON giveaways(category);
CREATE INDEX IF NOT EXISTS idx_giveaways_draw_at ON giveaways(draw_at);

-- ------------------------------------------------------------------------------
-- 3. PARTICIPATION CODES
-- ------------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS codes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    giveaway_id UUID NOT NULL REFERENCES giveaways(id) ON DELETE CASCADE,
    code VARCHAR(50) UNIQUE NOT NULL,
    is_used BOOLEAN NOT NULL DEFAULT false,
    used_by UUID REFERENCES users(id) ON DELETE SET NULL,
    used_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_codes_code ON codes(code);
CREATE INDEX IF NOT EXISTS idx_codes_giveaway_id ON codes(giveaway_id);
CREATE INDEX IF NOT EXISTS idx_codes_is_used ON codes(is_used);

-- ------------------------------------------------------------------------------
-- 4. DIGITAL TICKETS
-- ------------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS tickets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ticket_number VARCHAR(50) NOT NULL,
    giveaway_id UUID NOT NULL REFERENCES giveaways(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    code_id UUID NOT NULL REFERENCES codes(id) ON DELETE RESTRICT,
    status VARCHAR(30) NOT NULL DEFAULT 'waiting_for_draw' CHECK (status IN ('eligible', 'waiting_for_draw', 'winner', 'not_selected')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_giveaway_ticket_number UNIQUE (giveaway_id, ticket_number),
    CONSTRAINT uq_giveaway_user UNIQUE (giveaway_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_tickets_giveaway_id ON tickets(giveaway_id);
CREATE INDEX IF NOT EXISTS idx_tickets_user_id ON tickets(user_id);
CREATE INDEX IF NOT EXISTS idx_tickets_status ON tickets(status);

-- ------------------------------------------------------------------------------
-- 5. DRAWS & BLOCKCHAIN PROOFS
-- ------------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS draws (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    giveaway_id UUID NOT NULL REFERENCES giveaways(id) ON DELETE CASCADE,
    total_tickets INT NOT NULL DEFAULT 0,
    drawn_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    seed_commitment TEXT,
    tx_hash VARCHAR(100),
    status VARCHAR(30) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'verified_onchain', 'failed')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_draws_giveaway_id ON draws(giveaway_id);

-- ------------------------------------------------------------------------------
-- 6. WINNERS
-- ------------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS winners (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    draw_id UUID NOT NULL REFERENCES draws(id) ON DELETE CASCADE,
    ticket_id UUID NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_draw_ticket UNIQUE (draw_id, ticket_id)
);

CREATE INDEX IF NOT EXISTS idx_winners_draw_id ON winners(draw_id);
CREATE INDEX IF NOT EXISTS idx_winners_user_id ON winners(user_id);

-- ------------------------------------------------------------------------------
-- 7. NOTIFICATIONS
-- ------------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    message TEXT NOT NULL,
    type VARCHAR(50) NOT NULL DEFAULT 'system',
    is_read BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_notifications_user_unread ON notifications(user_id, is_read);

-- ------------------------------------------------------------------------------
-- 8. USER ACTIVITY
-- ------------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS user_activity (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    activity_type VARCHAR(50) NOT NULL,
    description TEXT NOT NULL,
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_user_activity_user_time ON user_activity(user_id, created_at DESC);

-- ------------------------------------------------------------------------------
-- 9. GAME SCORES (Sensor Mini Game)
-- Note: Scores & gameplay NEVER affect lottery winning odds.
-- ------------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS game_scores (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE UNIQUE,
    score INT NOT NULL DEFAULT 0,
    xp INT NOT NULL DEFAULT 0,
    badge VARCHAR(50) NOT NULL DEFAULT 'Pemula',
    level INT NOT NULL DEFAULT 1,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_game_scores_score ON game_scores(score DESC);

-- ==============================================================================
-- 10. ATOMIC RPC FUNCTION: redeem_code
-- ==============================================================================

CREATE OR REPLACE FUNCTION redeem_code(
    p_session_token TEXT,
    p_code TEXT,
    p_user_lat DOUBLE PRECISION DEFAULT NULL,
    p_user_lng DOUBLE PRECISION DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_token_hash VARCHAR(64);
    v_user_id UUID;
    v_code RECORD;
    v_giveaway RECORD;
    v_existing_ticket INT;
    v_next_seq INT;
    v_ticket_number VARCHAR(50);
    v_ticket_id UUID;
    v_cos_val DOUBLE PRECISION;
    v_distance_km DOUBLE PRECISION;
BEGIN
    -- 1. Validate Session Token
    v_token_hash := encode(digest(p_session_token, 'sha256'), 'hex');
    
    SELECT user_id INTO v_user_id
    FROM sessions
    WHERE (token_hash = v_token_hash OR token_hash = p_session_token)
      AND revoked = false
      AND expires_at > now()
    LIMIT 1;

    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Sesi tidak valid atau telah kedaluwarsa. Silakan login kembali.'
        );
    END IF;

    -- 2. Validate Code Existence & Expiry (Row Lock)
    SELECT * INTO v_code
    FROM codes
    WHERE UPPER(TRIM(code)) = UPPER(TRIM(p_code))
    FOR UPDATE;

    IF v_code.id IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Kode partisipasi tidak ditemukan.'
        );
    END IF;

    IF v_code.is_used = true THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Kode partisipasi ini sudah pernah digunakan.'
        );
    END IF;

    IF v_code.expires_at < now() THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Kode partisipasi ini telah melewati batas masa berlaku (kedaluwarsa).'
        );
    END IF;

    -- 3. Validate Giveaway Status & Period (Row Lock)
    SELECT * INTO v_giveaway
    FROM giveaways
    WHERE id = v_code.giveaway_id
    FOR UPDATE;

    IF v_giveaway.id IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Campaign undian untuk kode ini tidak ditemukan.'
        );
    END IF;

    IF v_giveaway.status != 'active' THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Campaign undian saat ini sedang tidak aktif (Status: ' || v_giveaway.status || ').'
        );
    END IF;

    IF now() < v_giveaway.start_at THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Periode penukaran kode untuk campaign ini belum dimulai.'
        );
    END IF;

    IF now() > v_giveaway.end_at THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Periode penukaran kode untuk campaign ini telah berakhir.'
        );
    END IF;

    -- 4. Check User Limit (1 Ticket Per User Per Giveaway)
    SELECT count(*) INTO v_existing_ticket
    FROM tickets
    WHERE giveaway_id = v_giveaway.id
      AND user_id = v_user_id;

    IF v_existing_ticket > 0 THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Anda sudah memiliki tiket untuk campaign ini (Maksimal 1 tiket per pengguna).'
        );
    END IF;

    -- 5. Geo-Restriction Validation (Haversine Formula)
    IF v_giveaway.geo_restricted = true THEN
        IF p_user_lat IS NULL OR p_user_lng IS NULL THEN
            RETURN jsonb_build_object(
                'success', false,
                'error', 'Campaign ini mewajibkan verifikasi lokasi GPS, namun koordinat lokasi tidak ditemukan.'
            );
        END IF;

        -- Haversine formula calculation
        v_cos_val := cos(radians(v_giveaway.latitude)) * cos(radians(p_user_lat)) *
                     cos(radians(p_user_lng) - radians(v_giveaway.longitude)) +
                     sin(radians(v_giveaway.latitude)) * sin(radians(p_user_lat));
        
        -- Clamp to [-1.0, 1.0] for floating point boundary safety
        IF v_cos_val > 1.0 THEN v_cos_val := 1.0; END IF;
        IF v_cos_val < -1.0 THEN v_cos_val := -1.0; END IF;

        v_distance_km := 6371.0 * acos(v_cos_val);

        IF v_distance_km > v_giveaway.radius_km THEN
            RETURN jsonb_build_object(
                'success', false,
                'error', 'Lokasi Anda berada di luar jangkauan area campaign (' ||
                         round(v_distance_km::numeric, 1) || ' km dari lokasi, batas maksimal ' ||
                         v_giveaway.radius_km || ' km).'
            );
        END IF;
    END IF;

    -- 6. Generate Sequential Unique Ticket Number
    SELECT count(*) + 1 INTO v_next_seq
    FROM tickets
    WHERE giveaway_id = v_giveaway.id;

    v_ticket_number := 'TKT-' || UPPER(SUBSTRING(v_giveaway.category FROM 1 FOR 3)) || '-' || LPAD(v_next_seq::TEXT, 5, '0');

    -- 7. Mark Code as Used
    UPDATE codes
    SET is_used = true,
        used_by = v_user_id,
        used_at = now()
    WHERE id = v_code.id;

    -- 8. Create Ticket
    INSERT INTO tickets (
        ticket_number,
        giveaway_id,
        user_id,
        code_id,
        status,
        created_at
    ) VALUES (
        v_ticket_number,
        v_giveaway.id,
        v_user_id,
        v_code.id,
        'waiting_for_draw',
        now()
    ) RETURNING id INTO v_ticket_id;

    -- 9. Log User Activity
    INSERT INTO user_activity (
        user_id,
        activity_type,
        description,
        metadata
    ) VALUES (
        v_user_id,
        'REDEEM_CODE',
        'Berhasil menukarkan kode ' || v_code.code || ' untuk tiket #' || v_ticket_number,
        jsonb_build_object(
            'giveaway_id', v_giveaway.id,
            'giveaway_title', v_giveaway.title,
            'ticket_id', v_ticket_id,
            'ticket_number', v_ticket_number
        )
    );

    -- 10. Create Notification
    INSERT INTO notifications (
        user_id,
        title,
        message,
        type
    ) VALUES (
        v_user_id,
        'Tiket Undian Berhasil Diklaim!',
        'Selamat! Tiket #' || v_ticket_number || ' Anda telah aktif untuk undian ' || v_giveaway.title || '.',
        'ticket_claimed'
    );

    -- 11. Return Success Result
    RETURN jsonb_build_object(
        'success', true,
        'message', 'Kode berhasil divalidasi dan tiket undian telah diterbitkan!',
        'ticket', jsonb_build_object(
            'id', v_ticket_id,
            'ticket_number', v_ticket_number,
            'giveaway_id', v_giveaway.id,
            'giveaway_title', v_giveaway.title,
            'status', 'waiting_for_draw',
            'draw_at', v_giveaway.draw_at
        )
    );
END;
$$;

-- ==============================================================================
-- 11. ROW LEVEL SECURITY (RLS) POLICIES
-- ==============================================================================

-- Enable RLS on all tables
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE giveaways ENABLE ROW LEVEL SECURITY;
ALTER TABLE codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE draws ENABLE ROW LEVEL SECURITY;
ALTER TABLE winners ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_activity ENABLE ROW LEVEL SECURITY;
ALTER TABLE game_scores ENABLE ROW LEVEL SECURITY;

-- Public Catalog: Anyone (anon) can view giveaways, draws, and winners
CREATE POLICY "Public can view giveaways" ON giveaways FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY "Public can view draws" ON draws FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY "Public can view winners" ON winners FOR SELECT TO anon, authenticated USING (true);

-- Sensitive tables: Direct INSERT/UPDATE/DELETE from anon is blocked.
-- Access is performed through custom RPC functions with SECURITY DEFINER
-- or custom session verification.
CREATE POLICY "Anon can view tickets" ON tickets FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY "Anon can view game_scores" ON game_scores FOR SELECT TO anon, authenticated USING (true);
