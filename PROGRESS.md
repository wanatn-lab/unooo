สถานะงานต่อเนื่อง (2026-09-26): Phase 3 protected state sync เสร็จและ deploy
migration production แล้ว. Migration 0005 ใช้ per-seat capability token แบบสุ่ม
256-bit (เก็บเฉพาะ SHA-256) ปิด direct table access; migration 0006 เพิ่ม
`get_room_game` สำหรับค้นหาเกมของห้องผ่าน token ที่ถูกต้อง และ frontend
`gameSync.js` poll state/hand ที่ป้องกันไว้ พร้อม heartbeat สำหรับ bot takeover.
ตรวจ production แล้วว่า RPC มีอยู่และ anon เรียกได้ แต่ anon ไม่มีสิทธิ์ SELECT
ตาราง `games` หรือ `game_players` โดยตรง. โค้ดอยู่บน `main` ที่ commit
`f1c022a`; `netlify.toml` ที่ commit `fe55907` ล็อก publish directory เป็น
`frontend`. ต่อมา production deploy สำเร็จผ่าน Netlify deploy service:
deploy `6ab718964e08cc8a8278ebc0` สถานะ `ready`, URL
`https://unooo-lobby.netlify.app`. หน้าเว็บ production จึงมี frontend Phase 3
แล้ว. มีการ push test commit `7c195347` เข้า `main` หลังพยายามเชื่อม
Git แล้ว แต่ Netlify ยังไม่สร้าง deploy จาก Git ภายในรอบตรวจแรก (ประมาณหนึ่งนาที)
จึงยังต้องยืนยัน Repository link และ Continuous deployment ใน dashboard ก่อนจะถือว่า
auto deploy ใช้งานได้. Production ที่เผยแพร่อยู่ยังเป็น deploy แบบ API ที่สำเร็จ.

โค้ดเฟส 2 ถูก push แล้วที่ commit 65c1e76 และ tag phase-2-complete.เฟสที่ทำล่าสุด: เฟส 2 - Game Logic
สถานะ: ปิดเฟสแล้ว (2026-09-25) — แต่ "ปิดเฟส" ในที่นี้หมายถึงโค้ด+เทสเสร็จและ
พร้อมให้ push เท่านั้น รอบนี้ผู้ใช้ (project owner) ให้ agent อีกตัว (Codex)
เป็นคน commit/push ขึ้น GitHub และติด tag `phase-2-complete` เอง — งานฝั่งนี้
"ทำไฟล์ให้เสร็จและทดสอบให้ผ่าน" ไม่ได้ push/tag ให้จากที่นี่ (ดูหัวข้อ
"สิ่งที่ยังไม่ได้ทำในรอบนี้" ด้านล่าง)

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
- ยังไม่ได้ทดสอบร่วมกับ Supabase Realtime เลย (เฟส 3 ถึงจะทำ sync ระหว่างเล่น)
  ตอนนี้การเดินไพ่ทุกครั้งต้อง refresh/poll เอาข้อมูลใหม่เอง ยังไม่มีการ
  broadcast อัตโนมัติเหมือนที่ lobby ทำได้ในเฟส 1
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
- Security phase 3: migration 0005 deploy แล้วและโค้ดอยู่บน main. Security advisor
  ยังรายงาน anon-executable SECURITY DEFINER RPCs ซึ่งตั้งใจเปิดเป็น API และตรวจ
  capability token ภายใน; มี RLS-no-policy INFO เพราะ direct privileges ถูกถอน.
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

ขั้นตอนถัดไป: deploy main จาก Netlify dashboard (หรือเชื่อม CLI credential ที่ใช้ได้), แล้ว smoke-test create/join, host start game, และผู้เล่นที่สองตรวจพบเกมผ่าน browser จริง; จากนั้นทำ rate limiting และ XSS hardening.