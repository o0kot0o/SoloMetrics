# Feature Matrix

Status values: `SUPPORTED`, `PARTIAL`, `UNSUPPORTED`, `UNTESTED`. A status changes only with in-game evidence logged in [API_VALIDATION.md](API_VALIDATION.md).

## Capability flags

| Flag | Status | Evidence |
| --- | --- | --- |
| native_meter_available | SUPPORTED | `IsDamageMeterAvailable() → true` |
| player_totals_live_display | SUPPORTED (visual confirm pending) | secret total/DPS accepted by SetText/SetFormattedText/AbbreviateNumbers in combat |
| player_totals_postcombat_readable | SUPPORTED | readable at combat end +0s |
| spell_data_live_display | SUPPORTED (visual confirm pending) | secret spellID → GetSpellTexture/GetSpellName; SetValue/SetMinMaxValues accept secrets; rows pre-sorted |
| spell_data_postcombat_readable | SUPPORTED | readable at combat end +0s |
| source_owner_attribution | UNTESTED | |
| pet_breakdown_reliable | UNTESTED | |
| guardian_breakdown_reliable | UNTESTED | |
| sampleable_numeric_dps_live | UNTESTED | Community report says live curves are blocked; verify |
| postcombat_session_history | UNTESTED | |
| session_duration_available | SUPPORTED | `GetSessionDurationSeconds(Current)` readable even in combat |
| savedvariables_persist | UNTESTED | M0 `/sm version` load counter tests this across /reload, logout, restart |

## Product features

| Feature | Depends on | Status |
| --- | --- | --- |
| Personal damage / DPS | player_totals_* | UNTESTED |
| Per-spell damage / DPS | spell_data_* | UNTESTED |
| Spell share % | spell_data_postcombat_readable + player_totals_postcombat_readable | UNTESTED |
| Crit / hit / max hit stats | no known source | UNSUPPORTED until a source is found |
| DPS timeline (live) | sampleable_numeric_dps_live | UNTESTED |
| Post-fight trend | postcombat_session_history | UNTESTED |
| Training dummy interval DPS | interval-specific readable damage | UNTESTED |
| Pet / combined views | source_owner_attribution, pet_breakdown_reliable | UNTESTED |
| Profiles persist | savedvariables_persist | UNTESTED |
