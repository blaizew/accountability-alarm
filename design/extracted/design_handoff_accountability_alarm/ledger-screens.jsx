// ledger-screens.jsx — interactive screen components for LEDGER prototype
// All screens accept state + handlers; navigation lives in the App in Ledger.html.

// ─────────────────────────────────────────────────────────────
// Chrome bits
// ─────────────────────────────────────────────────────────────
function LTopBar({ left, right, onLeft, onRight }) {
  return (
    <div style={{
      display: "flex", alignItems: "center", justifyContent: "space-between", gap: 12,
      padding: "8px 16px", fontFamily: lFonts.mono, fontSize: 10.5,
      color: lPalette.dim, letterSpacing: 0.6, textTransform: "uppercase",
      borderBottom: `1px solid ${lPalette.hair}`, position: "relative", zIndex: 4,
      whiteSpace: "nowrap",
    }}>
      <div onClick={onLeft} style={{ cursor: onLeft ? "pointer" : "default", padding: "2px 0", color: onLeft ? lPalette.muted : lPalette.dim, overflow: "hidden", textOverflow: "ellipsis", flex: "1 1 auto", minWidth: 0 }}>{left}</div>
      <div onClick={onRight} style={{ cursor: onRight ? "pointer" : "default", padding: "2px 0", color: onRight ? lPalette.fg : lPalette.dim, flex: "0 0 auto" }}>{right}</div>
    </div>
  );
}

function LTitle({ kicker, title, count }) {
  return (
    <div style={{ padding: "16px 16px 14px" }}>
      <div style={{ fontFamily: lFonts.mono, fontSize: 10.5, color: lPalette.dim, letterSpacing: 0.6, textTransform: "uppercase", marginBottom: 6 }}>
        {kicker}
      </div>
      <div style={{ display: "flex", alignItems: "baseline", justifyContent: "space-between" }}>
        <div style={{ fontFamily: lFonts.mono, fontSize: 26, color: lPalette.fg, fontWeight: 500, letterSpacing: -0.4 }}>
          {title}
        </div>
        {count !== undefined && (
          <div style={{ fontFamily: lFonts.mono, fontSize: 11, color: lPalette.muted }}>
            [{count}]
          </div>
        )}
      </div>
    </div>
  );
}

function LTabBar({ active, onTab }) {
  const tabs = [["alarms","Alarms"], ["history","History"]];
  return (
    <div style={{
      position: "absolute", bottom: 0, left: 0, right: 0, height: 50,
      background: lPalette.bg2, borderTop: `1px solid ${lPalette.hair}`,
      display: "flex", alignItems: "center", justifyContent: "space-around",
      fontFamily: lFonts.mono, fontSize: 10.5, letterSpacing: 0.6, textTransform: "uppercase",
      zIndex: 5,
    }}>
      {tabs.map(([id, lbl]) => {
        const on = id === active;
        return (
          <div key={id} onClick={() => onTab(id)} style={{
            cursor: "pointer", color: on ? lPalette.fg : lPalette.dim,
            display: "flex", alignItems: "center", gap: 6, padding: "8px 16px",
          }}>
            {on && <lGlyph.dot size={5} />}
            {lbl}
          </div>
        );
      })}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// SCREEN — Alarm List
// ─────────────────────────────────────────────────────────────
function LList({ alarms, now, onFire, onEdit, onToggle, onNew, onTab, activeTab }) {
  const onCount = alarms.filter(a => a.on).length;
  const nextAlarm = alarms.filter(a => a.on).sort((a,b) => {
    // crude minutes-until comparison
    const mins = (al) => ((al.period === "PM" && al.hour !== 12 ? al.hour + 12 : al.hour) * 60 + (al.min || 0));
    return mins(a) - mins(b);
  })[0];
  return (
    <div
      data-screen-label="01 Alarm List"
      style={{ boxSizing: "border-box", height: "100%", background: lPalette.bg, color: lPalette.fg, paddingTop: 50, position: "relative", overflow: "hidden" }}
    >
      <LTopBar left={`ALARMS · ${onCount}/${alarms.length} ON`} right={now.replace("LOCAL ", "")} />
      <div style={{ overflowY: "auto", position: "absolute", top: 88, bottom: 50, left: 0, right: 0 }}>
        <LTitle kicker={nextAlarm ? `// next: ${nextAlarm.label.toLowerCase()} · ${nextAlarm.time} ${nextAlarm.period}` : "// no active alarms"} title="Alarms" count={alarms.length} />
        {alarms.map((a, i) => (
          <LAlarmRow key={a.id} a={a} i={i}
            onFire={() => onFire(a)} onEdit={() => onEdit(a.id)} onToggle={() => onToggle(a.id)} />
        ))}
        <div style={{ borderTop: `1px solid ${lPalette.hair}`, padding: "20px 16px", textAlign: "center" }}>
          <div onClick={onNew} style={{
            display: "inline-flex", alignItems: "center", gap: 8,
            padding: "10px 16px", border: `1px dashed ${lPalette.hair2}`,
            fontFamily: lFonts.mono, fontSize: 11, color: lPalette.muted,
            letterSpacing: 0.6, textTransform: "uppercase", cursor: "pointer",
          }}>
            <lGlyph.plus size={10} /> new commitment
          </div>
        </div>
        <div style={{ height: 20 }} />
      </div>

      <LTabBar active={activeTab} onTab={onTab} />
    </div>
  );
}

function LAlarmRow({ a, i, onFire, onEdit, onToggle }) {
  const styleColor =
    a.escalation === "gentle"     ? lPalette.ringNudge
  : a.escalation === "firm"       ? lPalette.ringMirror
  :                                 lPalette.ringPreview;

  const outcomeColor =
    a.lastOutcome === "complied"  ? lPalette.goodGreen
  : a.lastOutcome === "snoozed"   ? lPalette.warnYellow
  : a.lastOutcome === "ignored"   ? lPalette.dim
  :                                 lPalette.badRed;

  return (
    <div style={{
      borderTop: `1px solid ${lPalette.hair}`,
      padding: "14px 16px",
      opacity: a.on ? 1 : 0.55,
      position: "relative",
      cursor: "pointer",
      minWidth: 0,
    }} onClick={onEdit}>
      {a.on && <div style={{ position: "absolute", left: 0, top: 0, bottom: 0, width: 2, background: styleColor }} />}

      {/* meta line */}
      <div style={{
        display: "flex", alignItems: "center", justifyContent: "space-between", gap: 8,
        marginBottom: 6, fontFamily: lFonts.mono, fontSize: 10.5, color: lPalette.dim,
        letterSpacing: 0.4, textTransform: "uppercase", whiteSpace: "nowrap",
      }}>
        <div style={{ display: "flex", alignItems: "center", gap: 8, minWidth: 0, overflow: "hidden" }}>
          <span style={{ color: lPalette.muted }}>#{String(i+1).padStart(3,"0")}</span>
          <span>{a.daysLabel}</span>
          <span style={{ display: "flex", alignItems: "center", gap: 4, color: styleColor }}>
            {lStyleGlyph(a.escalation, 9, styleColor)} {a.escalation}
          </span>
        </div>
        <div style={{ display: "flex", alignItems: "center", gap: 10, flexShrink: 0 }} onClick={(e) => e.stopPropagation()}>
          {a.on && (
            <div onClick={onFire} style={{
              display: "flex", alignItems: "center", justifyContent: "center",
              width: 24, height: 18, border: `1px solid ${lPalette.hair2}`,
              color: lPalette.muted, cursor: "pointer", background: lPalette.bg,
            }} title="Demo: fire this alarm now">
              <lGlyph.play size={8} />
            </div>
          )}
          <div onClick={onToggle} style={{
            width: 30, height: 16, borderRadius: 8,
            background: a.on ? lPalette.fg : "transparent",
            border: `1px solid ${a.on ? lPalette.fg : lPalette.hair2}`,
            position: "relative", cursor: "pointer", transition: "background .15s",
          }}>
            <div style={{
              position: "absolute", top: 1, [a.on ? "right" : "left"]: 1,
              width: 12, height: 12, borderRadius: 6,
              background: a.on ? lPalette.bg : lPalette.dim,
              transition: "left .15s, right .15s",
            }} />
          </div>
        </div>
      </div>

      {/* time + label */}
      <div style={{ display: "flex", alignItems: "baseline", gap: 12, marginBottom: 8, minWidth: 0 }}>
        <div style={{
          fontFamily: lFonts.mono, fontSize: 32, fontWeight: 400, color: lPalette.fg,
          letterSpacing: -0.8, lineHeight: 1, fontVariantNumeric: "tabular-nums",
          display: "flex", alignItems: "baseline", gap: 4, flexShrink: 0,
        }}>
          {a.time}
          <span style={{ fontSize: 14, color: lPalette.muted }}>{a.period}</span>
        </div>
        <div style={{
          fontFamily: lFonts.mono, fontSize: 13, color: lPalette.muted,
          minWidth: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", flex: 1,
        }}>
          {a.label}
        </div>
      </div>

      {/* reason snippet */}
      <div style={{
        fontFamily: lFonts.mono, fontSize: 12, color: lPalette.muted,
        lineHeight: 1.5, marginBottom: 8, paddingLeft: 10,
        borderLeft: `1px solid ${lPalette.hair2}`,
      }}>
        "{a.reasonShort}"
      </div>

      {/* tail */}
      <div style={{ display: "flex", alignItems: "center", gap: 14, fontFamily: lFonts.mono, fontSize: 10.5, color: lPalette.dim }}>
        <span>last <span style={{ color: outcomeColor }}>● {a.lastOutcome}</span></span>
        <span>streak {a.streak}</span>
        <span style={{ marginLeft: "auto", color: lPalette.dimmer, display: "flex", alignItems: "center", gap: 3 }}>
          edit <lGlyph.chev size={8} />
        </span>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// SCREEN — Alarm Edit (interactive form)
// ─────────────────────────────────────────────────────────────
function LEdit({ alarm, onSave, onCancel, onDelete, isNew }) {
  const [draft, setDraft] = React.useState(alarm);
  React.useEffect(() => { setDraft(alarm); }, [alarm.id]);
  const dirty = JSON.stringify(draft) !== JSON.stringify(alarm);

  const toggleDay = (i) => {
    const has = draft.daysSet.includes(i);
    const next = has ? draft.daysSet.filter(x => x !== i) : [...draft.daysSet, i].sort();
    setDraft({ ...draft, daysSet: next });
  };

  return (
    <div
      data-screen-label="02 Alarm Edit"
      style={{ boxSizing: "border-box", height: "100%", background: lPalette.bg, color: lPalette.fg, paddingTop: 50, display: "flex", flexDirection: "column" }}
    >
      <LTopBar
        left={isNew ? "ALARMS / NEW" : "ALARMS / EDIT"}
        right={dirty ? "UNSAVED ●" : ""}
      />

      <div style={{ flex: 1, minHeight: 0, overflowY: "auto" }}>

      {/* top action bar */}
      <div style={{ display: "flex", justifyContent: "space-between", padding: "10px 16px", borderBottom: `1px solid ${lPalette.hair}`, fontFamily: lFonts.mono, fontSize: 12 }}>
        <div style={{ color: lPalette.muted, cursor: "pointer" }} onClick={onCancel}>Cancel</div>
        <div style={{ color: dirty ? lPalette.fg : lPalette.dim, fontWeight: 600, cursor: dirty ? "pointer" : "default" }} onClick={() => dirty && onSave(draft)}>
          Save →
        </div>
      </div>

      {/* time wheel — two columns, hours + minutes scroll independently */}
      <div style={{ padding: "16px", borderBottom: `1px solid ${lPalette.hair}` }}>
        <div style={{ fontFamily: lFonts.mono, fontSize: 10.5, color: lPalette.dim, letterSpacing: 0.6, textTransform: "uppercase", marginBottom: 12, textAlign: "center" }}>
          § 01 · Fires at
        </div>
        <LTimeWheel draft={draft} setDraft={setDraft} />
      </div>

      {/* days */}
      <div style={{ padding: "14px 16px", borderBottom: `1px solid ${lPalette.hair}` }}>
        <div style={{ fontFamily: lFonts.mono, fontSize: 10.5, color: lPalette.dim, letterSpacing: 0.6, textTransform: "uppercase", marginBottom: 10 }}>
          § 02 · Repeat
        </div>
        <div style={{ display: "flex", gap: 6, justifyContent: "space-between" }}>
          {DAYS_L.map((d, i) => {
            const on = draft.daysSet.includes(i);
            return (
              <div key={i} onClick={() => toggleDay(i)} style={{
                flex: 1, height: 38, borderRadius: 2,
                background: on ? lPalette.fg : "transparent",
                border: `1px solid ${on ? lPalette.fg : lPalette.hair2}`,
                display: "flex", alignItems: "center", justifyContent: "center",
                fontFamily: lFonts.mono, fontSize: 12, fontWeight: 600,
                color: on ? lPalette.bg : lPalette.muted,
                cursor: "pointer", transition: "background .12s",
              }}>{d}</div>
            );
          })}
        </div>
      </div>

      {/* reason — centerpiece */}
      <div style={{ padding: "14px 16px", background: lPalette.bg2, borderTop: `1px solid ${lPalette.hair2}`, borderBottom: `1px solid ${lPalette.hair2}` }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 10 }}>
          <div style={{ fontFamily: lFonts.mono, fontSize: 10.5, color: lPalette.fg, letterSpacing: 0.6, textTransform: "uppercase" }}>
            § 03 · Why this matters <span style={{ color: lPalette.dim }}>· required</span>
          </div>
        </div>

        <textarea
          value={draft.reason}
          onChange={(e) => setDraft({ ...draft, reason: e.target.value })}
          rows={5}
          style={{
            width: "100%", boxSizing: "border-box",
            fontFamily: lFonts.mono, fontSize: 13, lineHeight: 1.55,
            color: lPalette.fg, padding: "12px 14px",
            background: lPalette.bg, border: `1px solid ${lPalette.hair2}`,
            borderRadius: 0, resize: "none", outline: "none",
            caretColor: lPalette.fg,
          }}
        />

        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginTop: 10, fontFamily: lFonts.mono, fontSize: 10.5, color: lPalette.dim, letterSpacing: 0.4, textTransform: "uppercase" }}>
          <div>{draft.reason.split(/\s+/).filter(Boolean).length} words</div>
          <div style={{ display: "flex", alignItems: "center", gap: 5, color: lPalette.ringPreview, cursor: "pointer" }}>
            <lGlyph.dot size={6} c={lPalette.ringPreview} /> REC
          </div>
        </div>

        {/* waveform */}
        <div style={{ display: "flex", alignItems: "center", gap: 1.5, height: 26, marginTop: 8 }}>
          {Array.from({length: 64}).map((_, i) => {
            const seed = Math.sin(i * 1.37) * 0.5 + 0.5;
            const h = 4 + seed * 20;
            return <div key={i} style={{ flex: 1, height: h, background: i < 38 ? lPalette.fg : lPalette.dim, opacity: i < 38 ? 0.85 : 0.4 }} />;
          })}
        </div>
      </div>

      {/* label */}
      <div style={{ padding: "14px 16px", borderBottom: `1px solid ${lPalette.hair}` }}>
        <div style={{ fontFamily: lFonts.mono, fontSize: 10.5, color: lPalette.dim, letterSpacing: 0.6, textTransform: "uppercase", marginBottom: 8 }}>
          § 04 · Label
        </div>
        <input
          value={draft.label}
          onChange={(e) => setDraft({ ...draft, label: e.target.value })}
          style={{
            width: "100%", boxSizing: "border-box",
            fontFamily: lFonts.mono, fontSize: 15, color: lPalette.fg,
            background: "transparent", border: "none", outline: "none",
            padding: "4px 0", caretColor: lPalette.fg,
          }}
        />
      </div>

      {/* escalation */}
      <div style={{ padding: "14px 16px", borderBottom: `1px solid ${lPalette.hair}` }}>
        <div style={{ fontFamily: lFonts.mono, fontSize: 10.5, color: lPalette.dim, letterSpacing: 0.6, textTransform: "uppercase", marginBottom: 10 }}>
          § 05 · Escalation style
        </div>
        {STYLES_L.map((s) => {
          const sel = s.id === draft.escalation;
          const c = s.id === "gentle" ? lPalette.ringNudge : s.id === "firm" ? lPalette.ringMirror : lPalette.ringPreview;
          return (
            <div key={s.id} onClick={() => setDraft({ ...draft, escalation: s.id })} style={{
              display: "flex", alignItems: "center", gap: 12,
              padding: "10px 12px",
              background: sel ? lPalette.bg3 : "transparent",
              border: `1px solid ${sel ? lPalette.hair2 : "transparent"}`,
              marginBottom: 6, cursor: "pointer", transition: "background .12s",
            }}>
              <div style={{ width: 18, display: "flex", alignItems: "center", justifyContent: "center", color: c }}>
                {lStyleGlyph(s.id, 14, c)}
              </div>
              <div style={{ flex: 1 }}>
                <div style={{ fontFamily: lFonts.mono, fontSize: 13, color: lPalette.fg, fontWeight: sel ? 600 : 400 }}>
                  {s.label}
                </div>
                <div style={{ fontFamily: lFonts.mono, fontSize: 11, color: lPalette.dim, marginTop: 2 }}>
                  {s.desc}
                </div>
              </div>
              {sel && <div style={{ fontFamily: lFonts.mono, fontSize: 10.5, color: lPalette.fg }}>✓</div>}
            </div>
          );
        })}
      </div>

      {/* delete */}
      {!isNew && (
        <div style={{ padding: "20px 16px 30px" }}>
          <div onClick={onDelete} style={{
            padding: "10px 0", textAlign: "center",
            border: `1px solid ${lPalette.hair2}`,
            fontFamily: lFonts.mono, fontSize: 11, color: lPalette.badRed,
            letterSpacing: 0.6, textTransform: "uppercase", cursor: "pointer",
          }}>
            delete commitment
          </div>
        </div>
      )}
      <div style={{ height: 40 }}/>
      </div>

      {/* home-indicator safe area */}
      <div style={{ height: 34, background: lPalette.bg, flexShrink: 0 }}/>
    </div>
  );
}

// Helpers for the time wheel
function LTimeWheel({ draft, setDraft }) {
  const [h, m] = draft.time.split(":").map(Number);
  const ROW_H = 44;

  const setHour = (newH) => {
    const hh = ((newH - 1 + 12) % 12) + 1;
    setDraft({ ...draft, time: `${String(hh).padStart(2, "0")}:${String(m).padStart(2, "0")}` });
  };
  const setMinute = (newM) => {
    const mm = ((newM % 60) + 60) % 60;
    setDraft({ ...draft, time: `${String(h).padStart(2, "0")}:${String(mm).padStart(2, "0")}` });
  };

  return (
    <div style={{ display: "flex", alignItems: "center", justifyContent: "center", gap: 14, position: "relative" }}>
      <LWheelColumn value={h} onChange={setHour} pad={2} rangeMin={1} rangeMax={12} wrap />
      <div style={{
        fontFamily: lFonts.mono, fontSize: 38, color: lPalette.fg, fontWeight: 400,
        fontVariantNumeric: "tabular-nums", lineHeight: 1, paddingBottom: 4,
      }}>:</div>
      <LWheelColumn value={m} onChange={setMinute} pad={2} rangeMin={0} rangeMax={59} wrap />
      <div
        onClick={() => setDraft({ ...draft, period: draft.period === "AM" ? "PM" : "AM" })}
        style={{
          fontFamily: lFonts.mono, fontSize: 13, fontWeight: 600,
          color: lPalette.fg, marginLeft: 8,
          padding: "6px 10px", border: `1px solid ${lPalette.hair2}`,
          letterSpacing: 0.6, cursor: "pointer", background: lPalette.bg2,
        }}
      >{draft.period}</div>
    </div>
  );
}

// A single 3-row scroll-wheel column. Tap above selected = decrement.
// Tap below = increment. (The visual is iOS-like; full scrolling would
// be overkill for a prototype demo.)
function LWheelColumn({ value, onChange, pad = 2, rangeMin, rangeMax, wrap }) {
  const step = (delta) => {
    let next = value + delta;
    if (wrap) {
      const span = rangeMax - rangeMin + 1;
      next = ((next - rangeMin) % span + span) % span + rangeMin;
    } else {
      next = Math.max(rangeMin, Math.min(rangeMax, next));
    }
    onChange(next);
  };
  const fmt = (n) => String(n).padStart(pad, "0");
  const prev = wrap ? (value === rangeMin ? rangeMax : value - 1) : Math.max(rangeMin, value - 1);
  const next = wrap ? (value === rangeMax ? rangeMin : value + 1) : Math.min(rangeMax, value + 1);

  const rowStyle = {
    fontFamily: lFonts.mono, fontVariantNumeric: "tabular-nums",
    fontSize: 38, lineHeight: "44px", height: 44, letterSpacing: -1,
    textAlign: "center", cursor: "pointer", userSelect: "none",
  };
  return (
    <div style={{ width: 76, position: "relative", background: lPalette.bg }}>
      <div onClick={() => step(-1)} style={{ ...rowStyle, color: lPalette.dimmer, fontWeight: 300 }}>{fmt(prev)}</div>
      <div style={{
        ...rowStyle,
        color: lPalette.fg, fontWeight: 500,
        borderTop: `1px solid ${lPalette.hair2}`, borderBottom: `1px solid ${lPalette.hair2}`,
        background: lPalette.bg2,
      }}>{fmt(value)}</div>
      <div onClick={() => step(1)} style={{ ...rowStyle, color: lPalette.dimmer, fontWeight: 300 }}>{fmt(next)}</div>
    </div>
  );
}

// (legacy stubs left for any external references)
function prevTime(a) {
  const [h, m] = a.time.split(":").map(Number);
  let nm = m - 1, nh = h;
  if (nm < 0) { nm = 59; nh = h - 1; }
  if (nh < 1) nh = 12;
  return { h: String(nh).padStart(2,"0"), m: String(nm).padStart(2,"0") };
}
function nextTime(a) {
  const [h, m] = a.time.split(":").map(Number);
  let nm = m + 1, nh = h;
  if (nm > 59) { nm = 0; nh = h + 1; }
  if (nh > 12) nh = 1;
  return { h: String(nh).padStart(2,"0"), m: String(nm).padStart(2,"0") };
}

// ─────────────────────────────────────────────────────────────
// SCREEN — Conversation
// ─────────────────────────────────────────────────────────────
function LConv({ alarm, onResolve }) {
  const script = CONV_SCRIPTS[alarm.id] || CONV_SCRIPTS.a5;
  // Step = how many script items have been revealed. Start with 1 (first AI msg).
  const [step, setStep] = React.useState(1);
  const [mode, setMode] = React.useState("voice"); // voice | text
  const [draftText, setDraftText] = React.useState("");
  const [overridePrompt, setOverridePrompt] = React.useState(false);
  const [overrideText, setOverrideText] = React.useState("");
  const scrollRef = React.useRef(null);

  const visible = script.slice(0, step);
  const currentMsg = visible[visible.length - 1];
  const currentRingId = currentMsg ? currentMsg.ring : "nudge";
  const ringIdx = RINGS_L.findIndex(r => r.id === currentRingId);
  const exhausted = step >= script.length;

  // Auto-scroll
  React.useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }
  }, [step]);

  // Live timer (mm:ss elapsed since fire)
  const [elapsed, setElapsed] = React.useState(3);
  React.useEffect(() => {
    const t = setInterval(() => setElapsed(e => e + 1), 1000);
    return () => clearInterval(t);
  }, []);
  const offsetMin = RINGS_L[ringIdx].offsetMin;
  const elapsedMs = `${String(Math.floor(elapsed/60)).padStart(2,"0")}:${String(elapsed%60).padStart(2,"0")}`;

  const advance = () => {
    // Reveal one more user msg, then 700ms later the AI reply (if any)
    if (step >= script.length) return;
    setStep(s => Math.min(s + 1, script.length));
    setTimeout(() => setStep(s => Math.min(s + 1, script.length)), 700);
  };
  const onMicTap = () => advance();
  const onTextSend = () => { if (draftText.trim()) { setDraftText(""); advance(); } };

  // Background subtle hue per ring
  const ringBgWash =
    currentRingId === "preview" ? `radial-gradient(120% 60% at 50% 0%, oklch(0.36 0.13 28 / 0.22), transparent 60%), ${lPalette.bg}` :
    currentRingId === "mirror"  ? `radial-gradient(120% 60% at 50% 0%, oklch(0.36 0.10 50 / 0.16), transparent 60%), ${lPalette.bg}` :
    currentRingId === "math"    ? `radial-gradient(120% 60% at 50% 0%, oklch(0.35 0.06 90 / 0.10), transparent 60%), ${lPalette.bg}` :
    lPalette.bg;

  return (
    <div
      data-screen-label={`03 Conversation · ${RINGS_L[ringIdx].label}`}
      style={{ boxSizing: "border-box", height: "100%", background: ringBgWash, color: lPalette.fg, paddingTop: 50, position: "relative", overflow: "hidden" }}
    >
      <LTopBar
        left={
          <span style={{ color: currentRingId === "preview" ? lPalette.ringPreview : lPalette.muted, display: "inline-flex", alignItems: "center", gap: 5 }}>
            <lGlyph.dot size={5} c={currentRingId === "preview" ? lPalette.ringPreview : lPalette.fg} />
            ALARM FIRING · +{offsetMin > 0 ? offsetMin : 0}m · {elapsedMs}
          </span>
        }
        right={<span style={{ display: "inline-flex", alignItems: "center", gap: 4 }}>Dismiss <lGlyph.x size={9}/></span>}
        onRight={() => onResolve({ kind: "dismiss", alarmId: alarm.id })}
      />

      {/* RING METER */}
      <div style={{ padding: "10px 16px 12px", display: "flex", flexDirection: "column", gap: 8, borderBottom: `1px solid ${lPalette.hair}` }}>
        <div style={{ display: "flex", gap: 4 }}>
          {RINGS_L.map((r, i) => {
            const reached = i <= ringIdx;
            const current = i === ringIdx;
            return (
              <div key={r.id} style={{
                flex: 1, height: current ? 4 : 2,
                background: reached ? lRingColor(r.id) : lPalette.hair2,
                transition: "all .3s",
              }} />
            );
          })}
        </div>
        <div style={{ display: "flex", justifyContent: "space-between", fontFamily: lFonts.mono, fontSize: 10.5, color: lPalette.dim, letterSpacing: 0.6, textTransform: "uppercase" }}>
          <div style={{ color: lPalette.fg, display: "flex", alignItems: "center", gap: 6 }}>
            <span>Ring {ringIdx+1}/4</span>
            <span style={{ color: lRingColor(currentRingId) }}>· {RINGS_L[ringIdx].label}</span>
          </div>
          <div>{RINGS_L[ringIdx].sub}</div>
        </div>
      </div>

      {/* ALARM HEADER */}
      <div style={{ padding: "14px 16px", borderBottom: `1px solid ${lPalette.hair}` }}>
        <div style={{ fontFamily: lFonts.mono, fontSize: 10.5, color: lPalette.dim, letterSpacing: 0.6, textTransform: "uppercase", marginBottom: 4 }}>
          Now firing
        </div>
        <div style={{
          fontFamily: lFonts.mono, fontSize: 18, color: lPalette.fg, letterSpacing: -0.3, fontWeight: 500,
          whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis",
        }}>
          {alarm.time} {alarm.period} · {alarm.label}
        </div>
        <div style={{
          fontFamily: lFonts.mono, fontSize: 11, color: lPalette.muted, marginTop: 6,
          paddingLeft: 10, borderLeft: `1px solid ${lPalette.hair2}`, lineHeight: 1.5,
        }}>
          "{alarm.reasonShort}"
        </div>
      </div>

      {/* MESSAGES */}
      <div ref={scrollRef} style={{ position: "absolute", top: 220, bottom: 230, left: 0, right: 0, overflowY: "auto" }}>
        {visible.map((m, i) => (
          <LMessage key={i} msg={m} idx={i+1} />
        ))}
        {exhausted && (
          <div style={{ padding: "12px 16px", fontFamily: lFonts.mono, fontSize: 10, color: lPalette.dim, letterSpacing: 0.6, textTransform: "uppercase", textAlign: "center" }}>
            // past-self is out of arguments. it's up to you.
          </div>
        )}
      </div>

      {/* BOTTOM — input + outcomes (or override prompt overlay) */}
      {overridePrompt ? (
        <LOverridePrompt
          value={overrideText} setValue={setOverrideText}
          onCancel={() => { setOverridePrompt(false); setOverrideText(""); }}
          onConfirm={() => onResolve({ kind: "override", alarmId: alarm.id, reason: overrideText.trim() || "(no reason)" })}
        />
      ) : (
        <LConvBottom
          mode={mode} setMode={setMode}
          draftText={draftText} setDraftText={setDraftText}
          onMicTap={onMicTap} onTextSend={onTextSend}
          ringId={currentRingId}
          exhausted={exhausted}
          onComply={() => onResolve({ kind: "comply", alarmId: alarm.id })}
          onSnooze={() => onResolve({ kind: "snooze", alarmId: alarm.id })}
          onOverride={() => setOverridePrompt(true)}
        />
      )}
    </div>
  );
}

function LMessage({ msg, idx }) {
  const isAI = msg.role === "ai";
  const msgRingIdx = RINGS_L.findIndex(r => r.id === msg.ring);
  const aiWeight = msgRingIdx === 0 ? 400 : msgRingIdx === 1 ? 500 : msgRingIdx === 2 ? 600 : 700;
  const aiColor = lRingColor(msg.ring);
  return (
    <div style={{ padding: "10px 16px", borderBottom: `1px solid ${lPalette.hair}` }}>
      <div style={{ display: "flex", justifyContent: "space-between", marginBottom: 4, fontFamily: lFonts.mono, fontSize: 9.5, color: lPalette.dim, letterSpacing: 0.4, textTransform: "uppercase", whiteSpace: "nowrap" }}>
        <div style={{ color: isAI ? aiColor : lPalette.muted, overflow: "hidden", textOverflow: "ellipsis", minWidth: 0 }}>
          {isAI ? `> past-self · ${msg.ring}` : "you"}
        </div>
        <div style={{ flexShrink: 0, marginLeft: 8 }}>{String(idx).padStart(2,"0")}</div>
      </div>
      <div style={{
        fontFamily: lFonts.mono, fontSize: 14, lineHeight: 1.5,
        color: isAI ? lPalette.fg : lPalette.muted,
        fontWeight: isAI ? aiWeight : 400,
        paddingLeft: isAI ? 0 : 24,
      }}>
        {msg.text}
        {msg.cite && (
          <sup style={{ marginLeft: 4, color: aiColor, fontSize: 10, fontWeight: 400 }}>[1]</sup>
        )}
      </div>
      {msg.cite && (
        <div style={{ marginTop: 6, paddingLeft: 12, borderLeft: `2px solid ${aiColor}`, fontFamily: lFonts.mono, fontSize: 10.5, color: lPalette.muted, letterSpacing: 0.3 }}>
          [1] {msg.cite}
        </div>
      )}
    </div>
  );
}

function LConvBottom({ mode, setMode, draftText, setDraftText, onMicTap, onTextSend, ringId, exhausted, onComply, onSnooze, onOverride }) {
  return (
    <div style={{ position: "absolute", bottom: 0, left: 0, right: 0, background: lPalette.bg2, borderTop: `1px solid ${lPalette.hair2}`, paddingBottom: 30, zIndex: 3 }}>
      {/* mode toggle */}
      <div style={{ display: "flex", borderBottom: `1px solid ${lPalette.hair}` }}>
        {[["voice","● voice"], ["text","text"]].map(([id, lbl]) => (
          <div key={id} onClick={() => setMode(id)} style={{
            flex: 1, padding: "10px 0", textAlign: "center", cursor: "pointer",
            fontFamily: lFonts.mono, fontSize: 11,
            color: mode === id ? lPalette.fg : lPalette.dim,
            letterSpacing: 0.6, textTransform: "uppercase",
            borderBottom: mode === id ? `2px solid ${lPalette.fg}` : `2px solid transparent`,
          }}>{lbl}</div>
        ))}
      </div>

      {/* input area */}
      {mode === "voice" ? (
        <div style={{ padding: "18px 16px", display: "flex", alignItems: "center", gap: 16 }}>
          <div onClick={onMicTap} style={{
            width: 56, height: 56, borderRadius: 28,
            background: exhausted ? lPalette.bg3 : lRingColor(ringId),
            display: "flex", alignItems: "center", justifyContent: "center",
            flexShrink: 0, cursor: exhausted ? "default" : "pointer",
            opacity: exhausted ? 0.5 : 1, transition: "background .2s",
          }}>
            <lGlyph.mic size={22} c={lPalette.bg} />
          </div>
          <div style={{ flex: 1, display: "flex", flexDirection: "column", gap: 4 }}>
            <div style={{ display: "flex", alignItems: "center", gap: 2, height: 24 }}>
              {Array.from({length: 28}).map((_, i) => {
                const seed = Math.abs(Math.sin(i * 2.1 + ringId.length));
                return <div key={i} style={{ flex: 1, height: 3 + seed * 18, background: lRingColor(ringId), opacity: exhausted ? 0.15 : 0.25 + seed * 0.6 }} />;
              })}
            </div>
            <div style={{ fontFamily: lFonts.mono, fontSize: 10, color: lPalette.dim, letterSpacing: 0.4, textTransform: "uppercase" }}>
              {exhausted ? "say anything · or pick below" : "tap mic to speak"}
            </div>
          </div>
        </div>
      ) : (
        <div style={{ padding: "12px 16px", display: "flex", gap: 8 }}>
          <input
            value={draftText}
            onChange={e => setDraftText(e.target.value)}
            onKeyDown={e => { if (e.key === "Enter") onTextSend(); }}
            placeholder="type a reply…"
            style={{
              flex: 1, padding: "10px 12px",
              background: lPalette.bg, border: `1px solid ${lPalette.hair2}`,
              fontFamily: lFonts.mono, fontSize: 13, color: lPalette.fg,
              outline: "none", caretColor: lPalette.fg, borderRadius: 0,
            }}
          />
          <div onClick={onTextSend} style={{
            padding: "10px 14px", background: draftText.trim() ? lPalette.fg : lPalette.bg3,
            color: draftText.trim() ? lPalette.bg : lPalette.dim,
            fontFamily: lFonts.mono, fontSize: 11, letterSpacing: 0.6, textTransform: "uppercase",
            cursor: draftText.trim() ? "pointer" : "default", fontWeight: 600,
          }}>send →</div>
        </div>
      )}

      {/* outcomes */}
      <div style={{ display: "flex", gap: 6, padding: "0 16px 12px" }}>
        <div onClick={onSnooze} style={{ flex: 1, padding: "10px 0", textAlign: "center", border: `1px solid ${lPalette.hair2}`, fontFamily: lFonts.mono, fontSize: 10.5, color: lPalette.muted, letterSpacing: 0.6, textTransform: "uppercase", cursor: "pointer" }}>
          Snooze · 9m
        </div>
        <div onClick={onComply} style={{ flex: 1, padding: "10px 0", textAlign: "center", background: lPalette.fg, fontFamily: lFonts.mono, fontSize: 10.5, color: lPalette.bg, letterSpacing: 0.6, textTransform: "uppercase", fontWeight: 600, cursor: "pointer" }}>
          Comply ↑
        </div>
        <div onClick={onOverride} style={{ flex: 1, padding: "10px 0", textAlign: "center", border: `1px solid ${lPalette.hair2}`, fontFamily: lFonts.mono, fontSize: 10.5, color: lPalette.muted, letterSpacing: 0.6, textTransform: "uppercase", cursor: "pointer" }}>
          Override
        </div>
      </div>
    </div>
  );
}

function LOverridePrompt({ value, setValue, onCancel, onConfirm }) {
  return (
    <div style={{ position: "absolute", bottom: 0, left: 0, right: 0, background: lPalette.bg2, borderTop: `1px solid ${lPalette.hair2}`, paddingBottom: 30, zIndex: 3 }}>
      <div style={{ padding: "14px 16px 10px" }}>
        <div style={{ fontFamily: lFonts.mono, fontSize: 10.5, color: lPalette.badRed, letterSpacing: 0.6, textTransform: "uppercase", marginBottom: 8, display: "flex", alignItems: "center", gap: 6 }}>
          <lGlyph.dot size={6} c={lPalette.badRed}/> override · logged
        </div>
        <div style={{ fontFamily: lFonts.mono, fontSize: 13, color: lPalette.fg, lineHeight: 1.5, marginBottom: 10 }}>
          One line. Future-you will read this.
        </div>
        <input
          autoFocus
          value={value}
          onChange={e => setValue(e.target.value)}
          onKeyDown={e => { if (e.key === "Enter") onConfirm(); }}
          placeholder="e.g. on-call, pager fire"
          style={{
            width: "100%", boxSizing: "border-box",
            padding: "10px 12px",
            background: lPalette.bg, border: `1px solid ${lPalette.badRed}`,
            fontFamily: lFonts.mono, fontSize: 13, color: lPalette.fg,
            outline: "none", caretColor: lPalette.badRed, borderRadius: 0,
          }}
        />
      </div>
      <div style={{ display: "flex", gap: 6, padding: "0 16px 12px" }}>
        <div onClick={onCancel} style={{ flex: 1, padding: "10px 0", textAlign: "center", border: `1px solid ${lPalette.hair2}`, fontFamily: lFonts.mono, fontSize: 10.5, color: lPalette.muted, letterSpacing: 0.6, textTransform: "uppercase", cursor: "pointer" }}>
          Cancel
        </div>
        <div onClick={onConfirm} style={{ flex: 1, padding: "10px 0", textAlign: "center", background: lPalette.badRed, fontFamily: lFonts.mono, fontSize: 10.5, color: lPalette.bg, letterSpacing: 0.6, textTransform: "uppercase", fontWeight: 600, cursor: "pointer" }}>
          Override ✓
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// SCREEN — History
// ─────────────────────────────────────────────────────────────
function LHistory({ events, onTab, activeTab, onOpen }) {
  // Derive everything from events so numbers always reconcile.
  const total = events.length;
  const complied = events.filter(e => e.outcome === "complied" || e.outcome === "snoozed_then_complied").length;
  const compliedPct = total ? Math.round((complied / total) * 100) : 0;
  const totalSnoozes = events.reduce((s, e) => s + (e.snoozes || 0), 0);
  const avgSnoozes = total ? (totalSnoozes / total).toFixed(1) : "0.0";
  const compliedWithDur = events.filter(e => typeof e.durMin === "number");
  const avgComplyT = compliedWithDur.length
    ? Math.round(compliedWithDur.reduce((s, e) => s + e.durMin, 0) / compliedWithDur.length)
    : 0;
  const alarmCount = new Set(events.map(e => e.alarmId)).size;

  return (
    <div
      data-screen-label="04 History"
      style={{ boxSizing: "border-box", height: "100%", background: lPalette.bg, color: lPalette.fg, paddingTop: 50, position: "relative", overflow: "hidden" }}
    >
      <LTopBar left="HISTORY · LAST 30D" right="" />
      <div style={{ overflowY: "auto", position: "absolute", top: 88, bottom: 50, left: 0, right: 0 }}>
        <LTitle kicker={`// across ${alarmCount} alarm${alarmCount === 1 ? "" : "s"}`} title="History" />
        {/* stat trio */}
        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", borderTop: `1px solid ${lPalette.hair}`, borderBottom: `1px solid ${lPalette.hair}` }}>
          <div style={{ padding: "14px 12px", borderRight: `1px solid ${lPalette.hair}` }}>
            <div style={{ fontFamily: lFonts.mono, fontSize: 9.5, color: lPalette.dim, letterSpacing: 0.6, textTransform: "uppercase", marginBottom: 4 }}>complied</div>
            <div style={{ fontFamily: lFonts.mono, fontSize: 24, color: lPalette.goodGreen, fontWeight: 500, lineHeight: 1, fontVariantNumeric: "tabular-nums" }}>{compliedPct}<span style={{ fontSize: 14, color: lPalette.muted }}>%</span></div>
            <div style={{ fontFamily: lFonts.mono, fontSize: 9.5, color: lPalette.muted, marginTop: 4 }}>complied {complied}/{total}</div>
          </div>
          <div style={{ padding: "14px 12px", borderRight: `1px solid ${lPalette.hair}` }}>
            <div style={{ fontFamily: lFonts.mono, fontSize: 9.5, color: lPalette.dim, letterSpacing: 0.6, textTransform: "uppercase", marginBottom: 4 }}>avg snoozes</div>
            <div style={{ fontFamily: lFonts.mono, fontSize: 24, color: lPalette.fg, fontWeight: 500, lineHeight: 1, fontVariantNumeric: "tabular-nums" }}>{avgSnoozes}</div>
            <div style={{ fontFamily: lFonts.mono, fontSize: 9.5, color: lPalette.muted, marginTop: 4 }}>{totalSnoozes} total</div>
          </div>
          <div style={{ padding: "14px 12px" }}>
            <div style={{ fontFamily: lFonts.mono, fontSize: 9.5, color: lPalette.dim, letterSpacing: 0.6, textTransform: "uppercase", marginBottom: 4 }}>avg comply-t</div>
            <div style={{ fontFamily: lFonts.mono, fontSize: 24, color: lPalette.fg, fontWeight: 500, lineHeight: 1, fontVariantNumeric: "tabular-nums" }}>{avgComplyT}<span style={{ fontSize: 12, color: lPalette.muted }}>m</span></div>
            <div style={{ fontFamily: lFonts.mono, fontSize: 9.5, color: lPalette.muted, marginTop: 4 }}>{compliedWithDur.length} samples</div>
          </div>
        </div>

        {/* 28-day cells */}
        <div style={{ padding: "14px 16px", borderBottom: `1px solid ${lPalette.hair}` }}>
          <div style={{ display: "flex", justifyContent: "space-between", fontFamily: lFonts.mono, fontSize: 9.5, color: lPalette.dim, letterSpacing: 0.6, textTransform: "uppercase", marginBottom: 8 }}>
            <div>28-day pattern · row = week</div>
            <div>↓ today</div>
          </div>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(7, 1fr)", gap: 4 }}>
            {PATTERN_28.map((s, i) => {
              const c = s === "c" ? lPalette.goodGreen
                     : s === "s" ? lPalette.warnYellow
                     : s === "i" ? lPalette.dim
                     : s === "m" ? lPalette.ringMirror
                     : s === "p" ? lPalette.ringPreview
                     : lPalette.dim;
              return <div key={i} style={{
                aspectRatio: "1/1",
                background: c,
                opacity: s === "i" ? 0.28 : 1,
                outline: i === PATTERN_28.length - 1 ? `1px solid ${lPalette.fg}` : "none",
              }} />;
            })}
          </div>
          <div style={{ display: "flex", gap: 12, marginTop: 10, fontFamily: lFonts.mono, fontSize: 9.5, color: lPalette.dim, letterSpacing: 0.4, textTransform: "uppercase" }}>
            <Legend c={lPalette.goodGreen} l="kept" />
            <Legend c={lPalette.warnYellow} l="snoozed" />
            <Legend c={lPalette.ringMirror} l="mirror" />
            <Legend c={lPalette.ringPreview} l="preview" />
            <Legend c={lPalette.dim} l="missed" />
          </div>
        </div>

        {/* ledger */}
        <div>
          <div style={{ display: "flex", justifyContent: "space-between", padding: "8px 16px", fontFamily: lFonts.mono, fontSize: 9.5, color: lPalette.dim, letterSpacing: 0.6, textTransform: "uppercase", borderBottom: `1px solid ${lPalette.hair}` }}>
            <div>Recent</div>
            <div>outcome / ring</div>
          </div>
          {events.map((h, i) => {
            const c = h.outcome === "complied" ? lPalette.goodGreen
                    : h.outcome === "snoozed_then_complied" ? lPalette.warnYellow
                    : h.outcome === "overridden" ? lPalette.badRed
                    : lPalette.dim;
            return (
              <div key={h.id} onClick={() => onOpen && onOpen(h.id)} style={{
                display: "flex", alignItems: "center", gap: 10,
                padding: "10px 16px", borderBottom: `1px solid ${lPalette.hair}`,
                fontFamily: lFonts.mono, fontSize: 12, cursor: onOpen ? "pointer" : "default",
              }}>
                <div style={{ color: lPalette.dimmer, fontSize: 10, width: 22 }}>{String(i+1).padStart(2,"0")}</div>
                <div style={{ color: lPalette.muted, width: 78, fontSize: 11 }}>{h.date.replace(" · ", " ").replace("May ", "5/")}</div>
                <div style={{ color: lPalette.fg, flex: 1, fontSize: 12, minWidth: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
                  {h.time} <span style={{ color: lPalette.muted }}>· {h.label}</span>
                  {h.outcome === "overridden" && h.overrideReason && (
                    <span style={{ color: lPalette.dim }}> · "{h.overrideReason}"</span>
                  )}
                </div>
                {h.ring && <div style={{ width: 8, height: 8, background: lRingColor(h.ring), flexShrink: 0 }} />}
                <div style={{ color: c, fontSize: 10, letterSpacing: 0.4, textTransform: "uppercase", whiteSpace: "nowrap" }}>
                  {h.outcome.replace(/_/g, " ")}{h.snoozes ? ` ·${h.snoozes}` : ""}
                </div>
              </div>
            );
          })}
        </div>
        <div style={{ height: 20 }} />
      </div>

      <LTabBar active={activeTab} onTab={onTab} />
    </div>
  );
}

function Legend({ c, l }) {
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 4 }}>
      <div style={{ width: 7, height: 7, background: c }} /> {l}
    </div>
  );
}

Object.assign(window, {
  LList, LEdit, LConv, LHistory, LTopBar, LTitle, LTabBar,
});
