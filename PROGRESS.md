# Progress

## Phase 4 — Game Table UI

สถานะ: **ยังไม่ปิดเฟส** — โค้ดเสร็จและ commit ไว้ใน local `main` แล้ว
(`1b8acf1`, `cd04978`) แต่ยังขาด 2 อย่างที่ PROJECT.md บังคับก่อนปิดเฟส: (1)
push ขึ้น GitHub จริง และ (2) ทดสอบ 2 ผู้เล่นจริงผ่านเบราว์เซอร์ ทั้งสองอย่าง
ติดปัญหาโครงสร้างพื้นฐานที่อธิบายไว้ด้านล่าง ไม่ใช่บั๊กของโค้ด

สิ่งที่เสร็จ:
- Migration 0010 (additive) เพิ่ม `hand_count` ใน `game_player_public_state`
  และฟังก์ชันที่สร้าง type นี้ (`get_game_players`, `call_uno`,
  `catch_uno_failure`, `heartbeat`) — ไม่มีการลบ/เปลี่ยนความหมายของ table,
  RPC หรือกติกาใดๆ **Apply ขึ้น production Supabase แล้ว** และตรวจสอบผ่าน
  `pg_type`/`pg_attribute` และ security advisor แล้ว (ไม่มี finding ใหม่)
- `frontend/js/game.js` (ใหม่): หน้าโต๊ะไพ่เต็มรูปแบบ — มือของผู้เล่นเอง,
  กองทิ้ง/กองจั่ว, สีที่ใช้งานอยู่, ใครกำลังเดิน, ทิศทาง, สถานะผู้เล่นอื่น
  (เชื่อมต่อ/บอท/UNO/จำนวนไพ่), ปุ่ม play/draw/pass/call UNO/catch UNO,
  ตัวเลือกสีสำหรับ Wild, ยืนยันก่อนประกาศ UNO, และหน้าจอจบเกม เชื่อมต่อผ่าน
  `frontend/js/gameApi.js`/`gameSync.js` เท่านั้น (ไม่มี direct table access,
  ไม่มี public Realtime) ใช้ค่าที่ RPC คืนกลับมาทันที (play_card/pass_turn/
  call_uno/catch_uno_failure คืน row ที่เพิ่งเปลี่ยน) เพื่อให้ UI ตอบสนอง
  ทันทีแทนที่จะรอ poll รอบถัดไป (~2 วินาที) ซึ่ง poll รอบถัดไปจะ reconcile
  กับ state จริงเสมอ
- Loading/reconnect/error states ครบ: banner "Loading table…",
  "Reconnecting…" (เมื่อ poll error), banner แจ้งเมื่อบอทกำลังเล่นแทน
  (is_bot ของตัวเอง), banner error สำหรับ action ที่ล้มเหลว
- Reduced-motion: ใช้ CSS transition เบาๆ เท่านั้น (ไม่มี JS animation loop)
  จึงถูกครอบคลุมโดย `prefers-reduced-motion` และปุ่ม "Reduce motion" ที่มีอยู่
  เดิมโดยอัตโนมัติ — ไม่ต้องเขียนกลไกแยก
- `frontend/js/avatars.js` (ใหม่): แยก avatar list ออกจาก lobby.js เพื่อให้
  ผู้เล่นได้ avatar เดิมทั้งใน Lobby และ Game view
- `frontend/js/lobby.js`, `main.js`: ต่อ flow lobby → game view อัตโนมัติเมื่อ
  มีเกมเกิดขึ้น (ทั้งกรณีกดเริ่มเองและกรณี host คนอื่นเริ่ม หรือ refresh หน้า
  ระหว่างเกม)
- ไม่ได้แตะ game logic (`0004_phase2_game_logic.sql`) หรือ networking
  (`gameApi.js`/`gameSync.js`) ตามที่กำหนดไว้ นอกจาก migration 0010 ที่เป็น
  additive ล้วนๆ

สิ่งที่ยังไม่เสร็จ (บล็อกโดยโครงสร้างพื้นฐาน ไม่ใช่โค้ด):
- **Push ไป GitHub ถูกปฏิเสธ**: session นี้ไม่มีสิทธิ์เขียนของ GitHub สำหรับ
  `wanatn-lab/unooo` ต้องให้ org admin ติดตั้ง Claude GitHub App
  (https://github.com/apps/claude/installations/select_target) หรือเชื่อม
  GitHub ใหม่ใน Claude.ai settings ก่อน ถึงจะ push ได้ (และ Netlify
  auto-deploy จาก main ที่ผูกไว้แล้วจะทำงานตามปกติ)
- **ยังไม่ได้ทดสอบ 2 ผู้เล่นจริงผ่านเบราว์เซอร์**: sandbox นี้ยังต่อตรงไปยัง
  `*.supabase.co` ไม่ได้ (ข้อจำกัดเดิมจาก Phase 1-3) และการลอง deploy preview
  ตรงไปยัง Netlify จาก sandbox (bypass Git) ก็ถูกปฏิเสธโดย network policy
  ของ sandbox เช่นกัน (ยืนยันจาก proxy diagnostics ว่าเป็น org policy 403 ไม่ใช่
  บั๊ก) จึงต้อง push ขึ้นจริงก่อนถึงจะมีที่ deploy ให้ทดสอบได้
- Opponent hand-count badge ใช้ `hand_count` ใหม่ได้ครบแล้ว แต่ยังไม่เคยเห็น
  ทำงานจริงในเบราว์เซอร์เพราะเหตุผลด้านบน
- พบเอกสารไม่ตรงกันเล็กน้อย (ไม่เกี่ยวกับ Phase 4): production มี migration
  ชื่อ `phase1_fix_search_path` ที่ apply ไว้แล้วแต่ไม่มีไฟล์อยู่ใน
  `backend/supabase/migrations/` ของ repo — ไม่ได้แตะต้อง แค่บันทึกไว้

ไฟล์หลักที่แก้/เพิ่ม:
- `/backend/supabase/migrations/0010_phase4_hand_count.sql` (ใหม่, deploy แล้ว)
- `/frontend/js/game.js` (ใหม่)
- `/frontend/js/avatars.js` (ใหม่)
- `/frontend/js/lobby.js`, `/frontend/js/main.js` (แก้ไขเพื่อต่อ flow ไปหน้าเกม)
- `/frontend/index.html`, `/frontend/css/style.css` (เพิ่ม markup/สไตล์หน้าโต๊ะไพ่)
- `/backups/2026-09-26_phase4/` (backup migration + netlify.toml — ไม่ใช่
  closeout backup ตัวเต็ม เพราะเฟสยังไม่ปิด ดู README ในโฟลเดอร์นั้น)

เฟสถัดไปต้องเริ่มจาก: **ปิด Phase 4 ให้เสร็จก่อน** — pull code ล่าสุดจาก
`main` (หลังแก้สิทธิ์ push แล้ว), ทดสอบ 2 ผู้เล่นจริงผ่านเบราว์เซอร์บน
Netlify production, แล้วค่อยอัปเดตส่วนนี้เป็น "ปิดเฟสแล้ว" พร้อม tag
`phase-4-complete` จากนั้นจึงเริ่ม Phase 5 ตามที่ระบุไว้เดิม

## Phase 3 — Protected State Sync

สถานะ: **ปิดเฟสแล้ว** (2026-09-26)

สิ่งที่เสร็จ:
- Migration 0005 ใช้ per-seat capability token แบบสุ่ม 256-bit เก็บเฉพาะ
  SHA-256, ถอน direct table access และป้องกัน roster/game/hand ผ่าน narrow RPCs.
- Migration 0006 เพิ่ม `get_room_game` และ frontend `gameSync.js` ทำ
  protected polling state ทุก 2 วินาที พร้อม heartbeat สำหรับ bot takeover.
- Migration 0007–0008 ลบข้อมูลจาก test setup ที่หยุดก่อนจบแบบเจาะจง capability
  hash; migration 0009 เป็น production smoke test ที่สร้าง‑ตรวจ‑ลบ game สองที่นั่ง
  ภายใน transaction เดียว.
- Netlify production deploy พร้อมใช้งานที่ `https://unooo-lobby.netlify.app`;
  `netlify.toml` กำหนด publish directory เป็น `frontend` และ Git main
  auto-deploy ได้รับการยืนยันแล้ว.

การทดสอบที่ทำจริง:
- ตรวจ production RPC/privilege: `get_room_game` มีอยู่, anon เรียก RPC ได้,
  แต่ anon ไม่มีสิทธิ์ SELECT จาก `games` หรือ `game_players` โดยตรง.
- Production smoke test 2 ที่นั่ง: create room, join, start game, host/guest
  ค้นหา game เดียวกันผ่าน capability ของตนเอง, host อ่านมือ 7 ใบ, และ token ข้าม
  ที่นั่งถูกปฏิเสธ. ตรวจหลังจบแล้วไม่เหลือ smoke players หรือ rooms.
- Netlify deployment จาก `main` สถานะ ready และผูกกับ Git commit จริง.

Backup:
- `backups/2026-09-26_phase3/` เก็บสำเนา migrations 0005–0009 และ Netlify
  build configuration ณ เวลาปิดเฟส.

ขอบเขตที่ย้ายไปเฟสถัดไป:
- หน้าโต๊ะไพ่และ UI play/draw/pass/UNO ยังไม่มี; เป็น Phase 4 UI.
- การ sync ใช้ protected polling โดยตั้งใจ ไม่ใช้ public Realtime WebSocket
  เพราะ capability token ไม่ใช่ JWT.
- Room-creation rate limiting และ XSS hardening เป็น security follow-up.

## Phase 2 — Game Logic (historical)

สถานะ: ปิดเฟสแล้ว (2026-09-25), code อยู่บน main และ tag `phase-2-complete`.

สิ่งที่เสร็จ:
- Game state schema ครบ (2.1) — ตาราง `games` (deck, discard_pile, ทิศทาง,
  สีที่ใช้งานอยู่, ผู้เล่นที่กำลังเดิน, สถานะ, config สำหรับ house rules) และ
  `game_players` (มือไพ่ต่อคน, ลำดับที่นั่ง, สถานะบอท/การเชื่อมต่อ) — ไฟล์
  `backend/supabase/migrations/0003_phase2_game_schema.sql`
- Deck 108 ใบครบตามสัดส่วนจริง + shuffle จริง (ไม่ใช่สุ่มปลอมๆ) — ไฟล์
  `backend/supabase/migrations/0004_phase2_game_logic.sql` ฟังก์ชัน
  `_generate_deck()` / `_shuffle()`
- Start game / dealing (2.2) — แจกคนละ 7 ใบ, เปิดไพ่เริ่มกองทิ้ง (สุ่มใหม่ถ้า
  เจอ Wild), รองรับผู้เล่น 2-8 คน — ฟังก์ชัน `start_game()`
- Turn & move validation (2.3) — `play_card()` เช็คสี/เลข/สัญลักษณ์/Wild
  ก่อนอนุญาตเดิน, ปฏิเสธการเดินผิดด้วย error code ชัดเจน (ไม่ใช่เงียบๆ ไม่ทำ
  อะไร) และไม่ทำให้ state พัง; `draw_card()` / `pass_turn()` สำหรับกรณีไม่มี
  ไพ่เล่นได้
- ไพ่พิเศษครบทุกแบบ (2.4) — Skip, Reverse (2 คน = เหมือน Skip ตามกติกาทางการ),
  Draw 2 / Wild Draw 4 (คนถัดไปโดนบังคับจั่ว+ข้ามตา), Wild (เลือกสีใหม่ได้
  บังคับให้เลือกก่อนเดิน)
- เงื่อนไขชนะ + กติกา UNO (2.5) — เล่นไพ่ใบสุดท้ายชนะทันที; ลืมพูด UNO ตอน
  เหลือ 1 ใบ โดนคนอื่นจับได้ภายในเวลาที่ตั้งไว้ (ค่าเริ่มต้น 3 วินาที, ปรับได้
  ผ่าน config ไม่ใช่ค่าตายตัวในโค้ด) จะโดนบทลงโทษจั่วเพิ่ม (ค่าเริ่มต้น 2 ใบ,
  ปรับได้เช่นกัน)
- ระบบบอทเล่นแทน + reconnect (2.6) — ตรวจจับผู้เล่นเงียบเกินเวลาที่ตั้งไว้
  (ค่าเริ่มต้น 20 วินาที) ผ่านกลไก heartbeat ที่ฝั่ง client ควรเรียกทุกๆ 2-3
  วินาทีระหว่างอยู่ในหน้าเกม, บอทเล่นไพ่ใบแรกที่เล่นได้หรือจั่วถ้าไม่มี, เลือกสี
  Wild อัตโนมัติ; ผู้เล่นกลับมา heartbeat อีกครั้งจะได้คุมเกมคืนทันทีโดยมือไพ่/
  ตำแหน่งเดิมไม่เปลี่ยน
- Frontend wrapper บางๆ `frontend/js/gameApi.js` (ตามแพทเทิร์นเดียวกับ
  roomApi.js ของเฟส 1) ให้เฟสถัดไปเรียกใช้ได้ — ไม่มี UI/animation ใหม่ ตาม
  สโคปที่ระบุว่า "logic only" ของเฟสนี้

การทดสอบที่ทำจริง (ไม่ใช่แค่ compile ผ่าน):
- เขียนชุดทดสอบอัตโนมัติจริง 11 กลุ่ม ครอบคลุมทุกหัวข้อ 2.1-2.6 ในไฟล์
  `backend/supabase/tests/phase2_game_logic.test.sql` รันจริงกับ Postgres 16
  ตัวจริง (ไม่ใช่ mock) ผลลัพธ์: ผ่านทั้งหมด 11/11 (exit code 0, ข้อความสรุป
  "ALL PHASE 2 TESTS PASSED")
- ครอบคลุม: นับไพ่ 108 ใบ+สัดส่วนสี, แจกไพ่ถูกต้องกับผู้เล่น 2/3/4/8 คน,
  ปฏิเสธการเดินไพ่ผิด 3 รูปแบบ (นอกตา/ไพ่ไม่มีในมือ/ไพ่ไม่ตรงสี-เลข) โดยไม่ทำ
  state พัง, Skip/Reverse(3+คน)/Reverse(2คน)/Draw2/Wild4 ทีละแบบแยกกันด้วย
  state ที่จัดไว้ล่วงหน้าเพื่อเช็คผลลัพธ์ตรงเป๊ะ, ชนะทันทีเมื่อเล่นไพ่ใบ
  สุดท้าย, กติกา UNO ครบ (ลืมพูด→โดนจับได้→โดนจั่วเพิ่ม, พูดแล้ว→จับไม่ได้,
  เลยเวลาที่กำหนด→จับไม่ได้), และ bot takeover เต็มรูปแบบ (จำลอง disconnect
  นาน 1 ชั่วโมง → บอทเข้าเล่นแทนและเกมเดินต่อไม่ค้าง → จำลอง reconnect →
  ได้คุมเกมคืนพร้อมมือไพ่/ตำแหน่งเดิม)

ข้อจำกัดของการทดสอบรอบนี้ (สำคัญ ต้องอ่าน — เหมือนที่แจ้งไว้ในเฟส 1):
- Sandbox ที่ใช้รันงานนี้ยังคงถูกปิดกั้นเครือข่ายขาออกไปยัง *.supabase.co
  เหมือนเฟส 1 (ยืนยันด้วย curl ตรงไปที่ REST API จริงของโปรเจกต์ — ได้ 403
  จาก proxy) จึงไม่สามารถรันฟังก์ชันเหล่านี้กับฐานข้อมูล Supabase ตัวจริงจาก
  ในนี้ได้เลย
- แก้ปัญหาด้วยการตั้ง Postgres 16 ในเครื่อง sandbox เอง แล้วรัน migration
  ไฟล์เดียวกันเป๊ะๆ กับที่จะรันบน Supabase จริง (0001, 0003, 0004) จากนั้นรัน
  ชุดทดสอบกับฐานข้อมูลนั้น — เป็น Postgres เวอร์ชันเดียวกับที่ Supabase ใช้
  จริง (16) ดังนั้นพฤติกรรม SQL/plpgsql ที่ทดสอบผ่านควรตรงกับของจริง แต่
  **ยืนยันแล้วว่า migration เฟส 2 (0003/0004) ถูก deploy บน Supabase โปรเจกต์จริง**
  (Postgres 17.6) และ backend migrations ถูกบันทึกไว้ใน project history; ยังขาด
  การทดสอบเกมเต็มรูปแบบผ่าน UI จริง.
- Phase 3 แก้การ sync ด้วย protected polling ทุก 2 วินาที ไม่ใช้ public
  Realtime broadcast เพราะ seat capability token ไม่ใช่ JWT; ดูสรุป Phase 3 ด้านบน.
- เพิ่มปุ่ม `Start Game` เฉพาะ host ใน lobby (commit `84a6dbc`); เรียก
  `start_game()` ผ่าน `frontend/js/gameApi.js` และกดได้เมื่อมีผู้เล่นอย่างน้อย 2 คน.
  ตรวจ syntax แล้ว แต่ยังไม่ได้ smoke-test ผ่าน browser จริง. หน้าจอเล่นไพ่และ UI
  สำหรับ action ระหว่างเล่นยังไม่เชื่อมต่อ จึงยังเล่นครบวงจรจากหน้าเว็บไม่ได้.

สิ่งที่ยังไม่เสร็จ/รู้ว่ามีบั๊กหรือจงใจเลื่อน (ไม่ใช่ลืมทำ):
- บอทยังใช้ตรรกะพื้นฐานตามที่ PROJECT.md ระบุไว้ — เล่นไพ่ใบแรกที่เล่นได้
  หรือจั่วถ้าไม่มี ไม่มีกลยุทธ์ใดๆ (เช่น ไม่เก็บ Wild ไว้ท้ายๆ, ไม่เลือกสีตาม
  จำนวนไพ่คู่ต่อสู้)
- `must_challenge_draw4` มีอยู่ใน config แล้วแต่ **ยังไม่มีผลอะไรจริง** — ยังไม่
  ได้ทำกลไก "ท้าทาย Wild Draw 4" (เช็คว่าคนก่อนหน้ามีไพ่สีตรงกันจริงไหมตอนเล่น
  Wild Draw 4) เพราะเป็นฟีเจอร์ที่ใหญ่พอสมควร ตั้งใจเว้นไว้ให้ชัดเจนแทนที่จะ
  แกล้งทำเป็นว่าเสร็จแล้ว
- ยังไม่มีระบบลบ/ดึงผู้เล่นออกจากเกมกลางคัน (ถ้าผู้เล่นออกจากห้องจริงๆ ไม่ใช่
  แค่ disconnect ชั่วคราว ระบบนี้ยังไม่รองรับ มีแต่กรณี "หายไปชั่วคราวแล้วบอท
  เล่นแทน")
- Security Phase 3 ปิดแล้ว: SECURITY DEFINER RPCs ที่ anon เรียกได้เป็น API ที่
  ตั้งใจให้ตรวจ capability ภายใน; RLS-no-policy INFO เป็นผลจากการถอน direct
  table privileges.
- ยังต้อง smoke-test create/join และ roster ใน browser จริง; production DB ยังไม่มี
  room/player/game data จากการทดสอบ. Room-creation rate limiting และ XSS prevention
  เป็น hardening follow-up.
ไฟล์หลักที่แก้/เพิ่ม:
- /PROGRESS.md (ไฟล์นี้)
- /backend/README.md (เพิ่มหัวข้อ "Phase 2: game logic")
- /backend/supabase/migrations/0003_phase2_game_schema.sql (ใหม่)
- /backend/supabase/migrations/0004_phase2_game_logic.sql (ใหม่)
- /backend/supabase/tests/phase2_game_logic.test.sql (ใหม่ — ชุดทดสอบ 11 กลุ่ม)
- /frontend/js/gameApi.js (ใหม่)
- /backups/2026-09-25_phase2/schema_snapshot.sql, config_snapshot.md (ใหม่)
- /backend/supabase/migrations/0005_phase3_capability_security.sql (deploy แล้ว)
- /backend/supabase/migrations/0006_phase3_protected_state_sync.sql (deploy แล้ว)
- /backend/supabase/tests/phase3_protected_state_sync.test.sql (ใหม่ — ตรวจ RPC/privilege)
- /frontend/js/gameSync.js (ใหม่ — protected state polling + heartbeat)
- /netlify.toml (ล็อก publish directory เป็น frontend)

ขั้นตอนถัดไป: Phase 4 — สร้างหน้าโต๊ะไพ่และ UI สำหรับ play/draw/pass/UNO โดยใช้
protected state sync ที่ปิดแล้ว; rate limiting และ XSS hardening เป็นงาน hardening
ถัดไป.