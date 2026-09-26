# Progress

## Phase 4 — Game Table UI

สถานะ: **ปิดเฟสแล้ว (2026-09-26)** — tag `phase-4-complete`

สิ่งที่เสร็จ:
- Migration 0010 (additive) เพิ่ม `hand_count` ใน `game_player_public_state`
  และฟังก์ชันที่สร้าง type นี้ (`get_game_players`, `call_uno`,
  `catch_uno_failure`, `heartbeat`) — ไม่มีการลบ/เปลี่ยนความหมายของ table,
  RPC หรือกติกาใดๆ **Apply ขึ้น production Supabase แล้ว**
- `frontend/js/game.js` (ใหม่): หน้าโต๊ะไพ่เต็มรูปแบบ — มือของผู้เล่นเอง,
  กองทิ้ง/กองจั่ว, สีที่ใช้งานอยู่, ใครกำลังเดิน, ทิศทาง, สถานะผู้เล่นอื่น
  (เชื่อมต่อ/บอท/UNO/จำนวนไพ่), ปุ่ม play/draw/pass/call UNO/catch UNO,
  ตัวเลือกสีสำหรับ Wild, ยืนยันก่อนประกาศ UNO, และหน้าจอจบเกม เชื่อมต่อผ่าน
  `frontend/js/gameApi.js`/`gameSync.js` เท่านั้น (ไม่มี direct table access,
  ไม่มี public Realtime) ใช้ค่าที่ RPC คืนกลับมาทันที เพื่อให้ UI ตอบสนอง
  ทันทีแทนที่จะรอ poll รอบถัดไป (~2 วินาที) ซึ่ง poll รอบถัดไปจะ reconcile
  กับ state จริงเสมอ
- Loading/reconnect/error states ครบ และ reduced-motion ผ่าน CSS transition
  เบาๆ เท่านั้น (ไม่มี JS animation loop)
- `frontend/js/avatars.js` (ใหม่), `lobby.js`/`main.js` ต่อ flow lobby →
  game view อัตโนมัติ

การทดสอบที่ทำจริง (2 ผู้เล่นจริงผ่านเบราว์เซอร์ บน production จริง — ไม่ใช่ mock):
เปิด 2 แท็บ Chrome จริง เข้า `https://unooo-lobby.netlify.app` สร้างห้อง/join
ห้อง, host กด Start Game, ทั้งสองแท็บเข้าสู่ Game Table อัตโนมัติ, ทดสอบ:
- play_card ปกติ, Wild+เลือกสี (color-picker modal), Skip, Draw 2
  (forced-draw chain) — ทุกอันอัปเดต UI ทันทีจากค่าที่ RPC คืนกลับมา
- draw_card ตอนไม่มีไพ่เล่นได้ (toast "doesn't match, so you'll need to
  pass"), pass_turn, ผลัดตาไปมาถูกต้อง
- error state: คลิกไพ่ตอนไม่ใช่ตาตัวเอง → banner "It's not your turn."
- reconnect/bot-takeover: เกิดขึ้นเองหลายครั้งระหว่างทดสอบ (idle เกินเวลาที่
  ตั้งไว้ → บอทเล่นแทน → กลับมาเล่นเอง → คุมเกมคืนพร้อมมือไพ่เดิม) ตรงตามที่
  ออกแบบไว้ตั้งแต่ Phase 2/3
- **จบเกมจริง**: ผู้เล่นคนหนึ่งไพ่หมดมือจากการเล่น draw2/skip/draw2/ไพ่ปกติ
  ต่อกัน, server ตั้ง `status='finished'` และ `winner_id` ถูกต้อง, ทั้งสอง
  แท็บ render หน้า Game Over ถูกต้องอิสระต่อกัน ("You win! 🎉" ฝั่งผู้ชนะ,
  "Nat wins!" ฝั่งผู้แพ้) และหยุด poll ตามที่ออกแบบไว้
- ยืนยันด้วยว่า opponent เห็นได้แค่ `hand_count` ไม่เห็นไพ่จริงของอีกฝ่าย
  ทั้งจาก UI และจากรูปแบบข้อมูลที่ RPC คืนกลับมา

**ไม่ได้ทดสอบสดแบบเจาะจง**: flow "ประกาศ UNO" (`call_uno`) และปุ่ม "Catch!"
(`catch_uno_failure`) เพราะเกมจบด้วยการไพ่หมดมือก่อนที่ฝ่ายไหนจะค้างที่ไพ่ใบ
เดียวนานพอให้กดปุ่มเหล่านี้ ทดแทนด้วย: (ก) โค้ด `game.js` ใช้ pattern เดียวกับ
play/draw/pass ที่ทดสอบสดผ่านแล้วทุกอย่าง (เรียก RPC → ใช้ row ที่คืนมาทันที
→ poll รอบถัดไป reconcile) และ (ข) ชุดทดสอบอัตโนมัติของ Phase 2
(`backend/supabase/tests/phase2_game_logic.test.sql`) ที่ทดสอบกติกา UNO/catch/
บทลงโทษครบแล้วกับ Postgres จริง (11/11 ผ่าน) นี่คือช่องว่างจริงระหว่าง
"ทดสอบสดครบวงจร" กับ "ทดสอบด้วยโค้ด+server-side test" — ควรปิดช่องว่างนี้ด้วย
การทดสอบสดเฉพาะจุดถ้าสงสัยว่ามีบั๊กในอนาคต

**บั๊กที่พบระหว่างทดสอบสด และแก้ไปแล้วทั้งหมด (deploy ขึ้น production แล้ว)**:
1. `frontend/js/roomApi.js`: `getPlayers()` เรียก `getAccessToken()` แต่ไฟล์
   import แค่ `getOrCreateAccessToken` → throw ทุกครั้งที่โหลดรายชื่อผู้เล่น
   ทำให้ lobby ค้างที่ "0/8 players" มาตั้งแต่ Phase 1/3 (เพิ่งเจอเพราะนี่คือ
   การทดสอบผ่านเบราว์เซอร์จริงครั้งแรกของโปรเจกต์นี้) — แก้ด้วยการเพิ่ม
   import ให้ครบ
2. `frontend/css/style.css`: `.btn` และ `.modal-overlay` set `display` ตายตัว
   โดยไม่มี `[hidden]` exception ทำให้ปุ่ม/modal ที่ควรซ่อนอยู่ (color-picker,
   uno-confirm, game-over, reconnect-error) โผล่ทับหน้าโต๊ะไพ่ทั้งหมดทันทีที่
   เข้าเกม — แก้ด้วย `.btn[hidden]`/`.modal-overlay[hidden] { display:none }`
   ตาม pattern เดียวกับ `.view[hidden]` ที่มีอยู่แล้ว
3. Migration `0011_phase4_fix_forced_draw_uno_flag.sql`: `_apply_play_card()`
   ตอนบังคับให้คู่ต่อสู้จั่วจาก Draw 2/Wild Draw 4 ไม่ได้ reset `said_uno`
   ของฝ่ายที่โดนบังคับจั่ว ทำให้ badge "UNO!" ค้างผิดๆ แม้มือจะโตกลับไปเกิน 1
   ใบแล้ว (เจอจริงระหว่างทดสอบ, ยืนยันจาก DB ตรง) — ไม่กระทบการ catch จริง
   เพราะ `catch_uno_failure` เช็ค hand length=1 อยู่แล้ว เป็นบั๊ก UI/data
   consistency ไม่ใช่บั๊กกติกา — แก้แล้ว, apply ขึ้น production แล้ว,
   security advisor ไม่มี finding ใหม่

Migration `0012_phase4_remove_smoke_test_room.sql`: ลบห้องทดสอบ (`BD6351`)
ที่ใช้ทดสอบสดทิ้งหลังปิดเฟส (scoped ด้วย id+code เจาะจง, cascade ลบ
games/game_players/players ที่เกี่ยวข้องหมดแล้ว, ตรวจว่าเหลือ 0 แถวจริง)

ไฟล์หลักที่แก้/เพิ่ม:
- `/backend/supabase/migrations/0010_phase4_hand_count.sql` (ใหม่, deploy แล้ว)
- `/backend/supabase/migrations/0011_phase4_fix_forced_draw_uno_flag.sql` (ใหม่, deploy แล้ว)
- `/backend/supabase/migrations/0012_phase4_remove_smoke_test_room.sql` (ใหม่, deploy แล้ว)
- `/frontend/js/game.js`, `/frontend/js/avatars.js` (ใหม่)
- `/frontend/js/lobby.js`, `/frontend/js/main.js` (ต่อ flow ไปหน้าเกม)
- `/frontend/js/roomApi.js` (แก้บั๊ก import)
- `/frontend/index.html`, `/frontend/css/style.css` (markup/สไตล์หน้าโต๊ะไพ่
  + แก้บั๊ก `[hidden]`)
- `/backups/2026-09-26_phase4_closeout/` (closeout backup ตัวเต็ม — ดู README
  ในโฟลเดอร์นั้นสำหรับรายละเอียดครบทุกอย่างที่ทดสอบและบั๊กที่แก้)

เฟสถัดไปต้องเริ่มจาก: Phase 5 (ตามที่ระบุไว้เดิมในเอกสารโปรเจกต์) — คำแนะนำ:
ถ้ามีเวลา ควรทำการทดสอบสดเฉพาะจุดสำหรับ flow "Call UNO"/"Catch!" ที่ยังไม่ได้
ทดสอบสดในเฟสนี้ ก่อนหรือระหว่าง Phase 5 ก็ได้ตามความเหมาะสม

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