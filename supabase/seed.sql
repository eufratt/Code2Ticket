-- ==============================================================================
-- Code2Ticket - Seed Data
-- 1. Demo Users & Game Scores
-- 2. 6 Giveaways (Yogyakarta Region)
-- 3. 50 Participation Codes
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. SEED DEMO USERS (Password: password123 hashed via pgcrypto bcrypt)
-- ------------------------------------------------------------------------------

INSERT INTO users (
    id,
    username,
    email,
    password_hash
) VALUES
(
    '11111111-1111-1111-1111-111111111111',
    'demouser',
    'demo@code2ticket.app',
    crypt('password123', gen_salt('bf', 10))
),
(
    '22222222-2222-2222-2222-222222222222',
    'jogjagamer',
    'gamer@code2ticket.app',
    crypt('password123', gen_salt('bf', 10))
)
ON CONFLICT (email) DO NOTHING;

-- Initial Game Scores for demo users
INSERT INTO game_scores (
    user_id,
    score,
    xp,
    badge,
    level
) VALUES
(
    '11111111-1111-1111-1111-111111111111',
    1250,
    450,
    'Master Sensor',
    5
),
(
    '22222222-2222-2222-2222-222222222222',
    800,
    200,
    'Penjelajah',
    3
)
ON CONFLICT (user_id) DO NOTHING;

-- Initial Welcome Notification
INSERT INTO notifications (
    user_id,
    title,
    message,
    type
) VALUES
(
    '11111111-1111-1111-1111-111111111111',
    'Selamat Datang di Code2Ticket!',
    'Akun demo Anda telah aktif. Masukkan kode campaign pertamamu dan nantikan undian digital.',
    'system'
)
ON CONFLICT DO NOTHING;

-- ------------------------------------------------------------------------------
-- 2. SEED GIVEAWAYS (6 Giveaways around Yogyakarta)
-- ------------------------------------------------------------------------------

INSERT INTO giveaways (
    id,
    title,
    category,
    prize_name,
    prize_value_usd,
    description,
    latitude,
    longitude,
    radius_km,
    geo_restricted,
    start_at,
    end_at,
    draw_at,
    winner_count,
    status
) VALUES
(
    'a1111111-1111-4111-8111-111111111111',
    'Jogja Tech Fest 2026: MacBook Pro M3 Max',
    'Tech',
    'Apple MacBook Pro 16" M3 Max (36GB / 1TB)',
    2499.00,
    'Undian digital khusus partisipan seminar Jogja Digital Tech Summit. Tukarkan kode Anda dan nantikan live draw terverifikasi on-chain!',
    -7.782884,
    110.367069,
    15.0,
    true,
    now() - interval '2 days',
    now() + interval '30 days',
    now() + interval '31 days',
    1,
    'active'
),
(
    'b2222222-2222-4222-8222-222222222222',
    'PlayStation 5 Pro & PS VR2 Grand Arena Quest',
    'Gaming',
    'Sony PlayStation 5 Pro + PS VR2 Horizon Bundle',
    899.00,
    'Campaign kolaborasi komunitas gamer dan merchant game center Pakuwon Mall Jogja. Terbuka untuk seluruh gamer Indonesia!',
    -7.758832,
    110.399587,
    10.0,
    false,
    now() - interval '1 days',
    now() + interval '25 days',
    now() + interval '26 days',
    1,
    'active'
),
(
    'c3333333-3333-4333-8333-333333333333',
    'Eksplorasi Malioboro: Liburan Mewah 3D2N ke Bali',
    'Travel',
    'Paket Liburan Mewah 3D2N Bali (Flight + Resort Bintang 5)',
    1200.00,
    'Khusus pengunjung kawasan wisata Malioboro dan UMKM partner. Wajib verifikasi lokasi GPS saat menukarkan kode tiket.',
    -7.792823,
    110.365842,
    8.0,
    true,
    now() - interval '3 days',
    now() + interval '20 days',
    now() + interval '21 days',
    2,
    'active'
),
(
    'd4444444-4444-4444-8444-444444444444',
    'UGM Heritage Fest: Voucher Kuliner & Kopi 1 Tahun',
    'Food',
    'Kartu Langganan Kuliner & Cafe Eksklusif 1 Tahun',
    500.00,
    'Nikmati aneka hidangan legendaris gudeg dan kedai kopi seputar kampus UGM sepanjang tahun. Tukarkan voucher partisipasi sekarang.',
    -7.771385,
    110.377626,
    12.0,
    false,
    now() - interval '1 days',
    now() + interval '14 days',
    now() + interval '15 days',
    3,
    'active'
),
(
    'e5555555-5555-4555-8555-555555555555',
    'Alkid Night Festival: Motor Honda Vario 160 ABS',
    'Automotive',
    'Sepeda Motor Honda Vario 160cc ABS 2026',
    1850.00,
    'Hadiah utama pesta rakyat Alun-Alun Kidul Yogyakarta. Syarat partisipasi berada dalam radius area kota Yogyakarta.',
    -7.811883,
    110.363223,
    20.0,
    true,
    now() - interval '4 days',
    now() + interval '40 days',
    now() + interval '41 days',
    1,
    'active'
),
(
    'f6666666-6666-4666-8666-666666666666',
    'Prambanan Creative Hub: Sony Alpha 7 IV Creator Kit',
    'Lifestyle',
    'Kamera Sony A7 IV Full-Frame + Lensa 24-70mm GM',
    2799.00,
    'Kompetisi konten kreator dan pengunjung situs warisan budaya Prambanan. Menangkan kamera mirrorless flagship.',
    -7.752020,
    110.491467,
    25.0,
    false,
    now() - interval '2 days',
    now() + interval '35 days',
    now() + interval '36 days',
    1,
    'active'
)
ON CONFLICT (id) DO NOTHING;

-- ------------------------------------------------------------------------------
-- 3. SEED 50 PARTICIPATION CODES
-- ------------------------------------------------------------------------------

INSERT INTO codes (giveaway_id, code, is_used, expires_at) VALUES
-- Tech Fest Codes (9 Codes)
('a1111111-1111-4111-8111-111111111111', 'TECH-JOG-001', false, now() + interval '60 days'),
('a1111111-1111-4111-8111-111111111111', 'TECH-JOG-002', false, now() + interval '60 days'),
('a1111111-1111-4111-8111-111111111111', 'TECH-JOG-003', false, now() + interval '60 days'),
('a1111111-1111-4111-8111-111111111111', 'TECH-JOG-004', false, now() + interval '60 days'),
('a1111111-1111-4111-8111-111111111111', 'TECH-JOG-005', false, now() + interval '60 days'),
('a1111111-1111-4111-8111-111111111111', 'TECH-JOG-006', false, now() + interval '60 days'),
('a1111111-1111-4111-8111-111111111111', 'TECH-JOG-007', false, now() + interval '60 days'),
('a1111111-1111-4111-8111-111111111111', 'TECH-JOG-008', false, now() + interval '60 days'),
('a1111111-1111-4111-8111-111111111111', 'TECH-JOG-009', false, now() + interval '60 days'),

-- Gaming Arena Codes (8 Codes)
('b2222222-2222-4222-8222-222222222222', 'GAME-PKW-001', false, now() + interval '60 days'),
('b2222222-2222-4222-8222-222222222222', 'GAME-PKW-002', false, now() + interval '60 days'),
('b2222222-2222-4222-8222-222222222222', 'GAME-PKW-003', false, now() + interval '60 days'),
('b2222222-2222-4222-8222-222222222222', 'GAME-PKW-004', false, now() + interval '60 days'),
('b2222222-2222-4222-8222-222222222222', 'GAME-PKW-005', false, now() + interval '60 days'),
('b2222222-2222-4222-8222-222222222222', 'GAME-PKW-006', false, now() + interval '60 days'),
('b2222222-2222-4222-8222-222222222222', 'GAME-PKW-007', false, now() + interval '60 days'),
('b2222222-2222-4222-8222-222222222222', 'GAME-PKW-008', false, now() + interval '60 days'),

-- Travel Malioboro Codes (8 Codes)
('c3333333-3333-4333-8333-333333333333', 'TRAV-MLB-001', false, now() + interval '60 days'),
('c3333333-3333-4333-8333-333333333333', 'TRAV-MLB-002', false, now() + interval '60 days'),
('c3333333-3333-4333-8333-333333333333', 'TRAV-MLB-003', false, now() + interval '60 days'),
('c3333333-3333-4333-8333-333333333333', 'TRAV-MLB-004', false, now() + interval '60 days'),
('c3333333-3333-4333-8333-333333333333', 'TRAV-MLB-005', false, now() + interval '60 days'),
('c3333333-3333-4333-8333-333333333333', 'TRAV-MLB-006', false, now() + interval '60 days'),
('c3333333-3333-4333-8333-333333333333', 'TRAV-MLB-007', false, now() + interval '60 days'),
('c3333333-3333-4333-8333-333333333333', 'TRAV-MLB-008', false, now() + interval '60 days'),

-- Culinary UGM Codes (8 Codes)
('d4444444-4444-4444-8444-444444444444', 'FOOD-UGM-001', false, now() + interval '60 days'),
('d4444444-4444-4444-8444-444444444444', 'FOOD-UGM-002', false, now() + interval '60 days'),
('d4444444-4444-4444-8444-444444444444', 'FOOD-UGM-003', false, now() + interval '60 days'),
('d4444444-4444-4444-8444-444444444444', 'FOOD-UGM-004', false, now() + interval '60 days'),
('d4444444-4444-4444-8444-444444444444', 'FOOD-UGM-005', false, now() + interval '60 days'),
('d4444444-4444-4444-8444-444444444444', 'FOOD-UGM-006', false, now() + interval '60 days'),
('d4444444-4444-4444-8444-444444444444', 'FOOD-UGM-007', false, now() + interval '60 days'),
('d4444444-4444-4444-8444-444444444444', 'FOOD-UGM-008', false, now() + interval '60 days'),

-- Automotive Alkid Codes (8 Codes)
('e5555555-5555-4555-8555-555555555555', 'MOTO-ALK-001', false, now() + interval '60 days'),
('e5555555-5555-4555-8555-555555555555', 'MOTO-ALK-002', false, now() + interval '60 days'),
('e5555555-5555-4555-8555-555555555555', 'MOTO-ALK-003', false, now() + interval '60 days'),
('e5555555-5555-4555-8555-555555555555', 'MOTO-ALK-004', false, now() + interval '60 days'),
('e5555555-5555-4555-8555-555555555555', 'MOTO-ALK-005', false, now() + interval '60 days'),
('e5555555-5555-4555-8555-555555555555', 'MOTO-ALK-006', false, now() + interval '60 days'),
('e5555555-5555-4555-8555-555555555555', 'MOTO-ALK-007', false, now() + interval '60 days'),
('e5555555-5555-4555-8555-555555555555', 'MOTO-ALK-008', false, now() + interval '60 days'),

-- Lifestyle Prambanan Codes (9 Codes)
('f6666666-6666-4666-8666-666666666666', 'LIFE-PRM-001', false, now() + interval '60 days'),
('f6666666-6666-4666-8666-666666666666', 'LIFE-PRM-002', false, now() + interval '60 days'),
('f6666666-6666-4666-8666-666666666666', 'LIFE-PRM-003', false, now() + interval '60 days'),
('f6666666-6666-4666-8666-666666666666', 'LIFE-PRM-004', false, now() + interval '60 days'),
('f6666666-6666-4666-8666-666666666666', 'LIFE-PRM-005', false, now() + interval '60 days'),
('f6666666-6666-4666-8666-666666666666', 'LIFE-PRM-006', false, now() + interval '60 days'),
('f6666666-6666-4666-8666-666666666666', 'LIFE-PRM-007', false, now() + interval '60 days'),
('f6666666-6666-4666-8666-666666666666', 'LIFE-PRM-008', false, now() + interval '60 days'),
('f6666666-6666-4666-8666-666666666666', 'LIFE-PRM-009', false, now() + interval '60 days')
ON CONFLICT (code) DO NOTHING;
