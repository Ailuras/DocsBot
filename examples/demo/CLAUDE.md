# Demo Project — Data Format Reference

This is a **sample project** shipped with DocsBot to demonstrate the data format. When creating your own project, copy this structure and replace the content.

## File Structure

```
projects/your-project/
  data/
    meta.js       -- Project identity, nav, stages, external links
    research.js   -- Research directions (R1, R2, ...)
    backlog.js    -- Engineering tasks (P0-01, P1-02, ...)
    roadmap.js    -- Weekly planning
    changelog.js  -- Commit history
    notes.js      -- Note index
  notes/
    *.html        -- Individual notes
```

## Data Files

All `.js` files in `data/` are plain JavaScript that assign to `window.AUGUR_*` globals. The frontend parses them in a sandbox (`new Function`) and extracts the variables.

### meta.js

Defines `window.AUGUR_META` with project metadata.

### research.js

Defines `window.AUGUR_RESEARCH` — an array of research direction objects.

Key fields: `id`, `codename`, `title`, `kind`, `module`, `hypothesis`, `body[]`, `depends_on[]`, `status`.

### backlog.js

Defines `window.AUGUR_BACKLOG_BUCKETS` (array of bucket definitions) and `window.AUGUR_BACKLOG` (array of task objects).

Key fields: `id`, `bucket`, `module`, `title`, `size`, `effort`, `serves[]`, `fields{input,output,accept,note}`, `status`.

### notes.js

Defines `window.AUGUR_NOTES` — an array of note index entries. Each entry points to an HTML file in `notes/`.

Key fields: `slug`, `title`, `date`, `path`, `tags[]`, `excerpt`.

## Notes

Notes are standalone HTML files. They are rendered inside a modal using `innerHTML`. You can use any HTML, CSS, tables, and inline styles.
