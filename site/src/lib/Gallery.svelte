<script>
  // Every ornament kind the package registers (lua/flora/gallery.lua),
  // drawn by the package's own Lua for three seeds, labelled with the name
  // that ornaments={...} weighs it by. Tabs narrow the sheet to one slot.
  import { onMount } from "svelte";
  import { gallery, meta, show as picture, px } from "./render.js";
  import COLOURWAYS from "./colourways.json";

  let canvas, frame;
  let sheet = $state(null);
  let way = $state(-1);
  let base = $state(0);
  let status = $state("");
  let busy = $state(false);
  let slots = $state([]);
  let slot = $state("flourish");
  let started = false;
  const about = $derived(slots.find((s) => s.name === slot));

  async function show() {
    if (busy) return;
    busy = true;
    status = "Drawing…";
    try {
      const palette = way < 0 ? {} : (await meta()).colourways[COLOURWAYS[way].key];
      const out = await gallery({ palette, spin: 0, base, slot, px: px(frame.clientWidth) });
      await picture(out, canvas, frame.clientWidth);
      sheet = { w: out.w, h: out.h, cells: out.cells };
      slots = out.slots;
      status = `${out.cells.length} kinds`;
    } catch (e) {
      status = `Something went wrong: ${e.message}`;
    }
    busy = false;
  }

  // Draw once the section comes near the screen; the sheet is large.
  onMount(() => {
    const seen = new IntersectionObserver((es) => {
      if (es.some((e) => e.isIntersecting) && !started) {
        started = true;
        seen.disconnect();
        show();
      }
    }, { rootMargin: "600px" });
    seen.observe(frame);
    return () => seen.disconnect();
  });
</script>

<div class="gallery">
<div class="tabs" role="tablist" aria-label="Places on the page">
  {#each slots.length ? slots : [{ name: "flourish", label: "Flourish" }] as s}
    <button type="button" role="tab" aria-selected={slot === s.name} disabled={busy && slot !== s.name}
      onclick={() => { if (slot !== s.name) { slot = s.name; show(); } }}>{s.label}</button>
  {/each}
  <button type="button" role="tab" aria-selected={slot === ""} disabled={busy && slot !== ""} onclick={() => { if (slot !== "") { slot = ""; show(); } }}>All</button>
</div>
{#if about}<p class="about">{about.desc}</p>{/if}
<div class="bar">
  <label>
    <span>Inks</span>
    <select bind:value={way} onchange={show} disabled={busy}>
      <option value={-1}>Original blue</option>
      {#each COLOURWAYS as c, i}<option value={i}>{c.name}</option>{/each}
    </select>
  </label>
  <button type="button" onclick={() => { base += 3; show(); }} disabled={busy}>New seeds</button>
  <span class="count" aria-live="polite">{status}</span>
</div>
<div class="plate paper" bind:this={frame} class:busy style:aspect-ratio={sheet ? `${sheet.w} / ${sheet.h}` : "600 / 2600"}>
  <canvas bind:this={canvas} aria-label={about ? `Every ${about.label.toLowerCase()} kind, three seeds each` : "Every ornament kind, three seeds each"}></canvas>
  {#if sheet}
    {#each sheet.cells as c}
      <span class="tag" style:left={`${(c.x / sheet.w) * 100}%`} style:top={`${(c.y / sheet.h) * 100}%`}>
        <span class="name">{c.label}</span> <code>{c.name}</code>
      </span>
    {/each}
  {/if}
</div>
</div>

<style>
  .gallery { min-width: 0; }
  /* The slots read as an index line of small capitals. */
  .tabs { display: flex; flex-wrap: wrap; gap: .1rem 1.1rem; margin: 0 0 .8rem; padding: .5rem 0; border-block: 1px solid var(--rule); }
  .tabs button { border: 0; padding: .2rem 0; min-height: 36px; font-variant-caps: all-small-caps; letter-spacing: .07em; font-size: 1.1rem; color: var(--muted); }
  .tabs button:hover:not(:disabled) { color: var(--ink); }
  .tabs button[aria-selected="true"] { color: var(--rubric); text-decoration: underline; text-underline-offset: .3em; text-decoration-thickness: 1px; }
  .about { margin: 0 0 .9rem; font-style: italic; max-width: 60ch; }
  .bar { display: flex; flex-wrap: wrap; gap: .6rem 1rem; align-items: center; margin: 0 0 1rem; }
  .bar label { display: flex; gap: .5rem; align-items: center; }
  .bar span { color: var(--muted); }
  .count { font-style: italic; }
  select, .bar button { border: 1px solid var(--control); background: transparent; padding: .3rem .7rem; min-height: 38px; border-radius: 0; }
  button { cursor: pointer; background: transparent; }
  button:disabled { opacity: .45; cursor: default; }
  /* The sheet is paper in both themes (app.css .paper): the ornaments and
     their labels are drawn for it. */
  .plate { position: relative; width: 100%; max-width: 760px; overflow: clip; box-shadow: 0 0 0 1px var(--rule); background: #fff; }
  .plate canvas { position: absolute; inset: 0; width: 100%; height: 100%; }
  .plate.busy canvas { opacity: .45; transition: opacity .3s; }
  .tag { position: absolute; transform: translateY(-100%); color: #2b2b2b; font-size: clamp(.66rem, 1.6vw, .86rem); white-space: nowrap; padding-bottom: 2px; }
  .tag code { color: #6f6a62; font-size: .9em; background: none; padding: 0; }
  @media (max-width: 860px) {
    button, select { min-height: 44px; }
    /* Narrow sheets keep only the name to weigh each kind by. */
    .tag .name { display: none; }
  }
</style>
