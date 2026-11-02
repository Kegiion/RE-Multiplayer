// MT-Explorer: Forschungswerkzeug fuer das Typsystem (DTI) von MT Framework.
//
// Jede Klasse der Engine hat ein statisches MtDTI-Objekt mit ihrem Namen.
// Jedes Objekt (MtObject) hat eine virtuelle Funktion getDTI(), die im Code
// meist so aussieht:  mov eax, <DTI-Adresse> ; ret   (B8 xx xx xx xx C3).
// Daran erkennen wir zu jedem Objekt im Speicher seine Klasse.
//
// Lua-API (globale Tabelle `mt`):
//   mt.scan()             -> Stand        startet die Speichersuche (DTI suchen + Objekte zuordnen)
//   mt.scan_step([ms=8])  -> Stand        arbeitet pro Aufruf hoechstens ms Millisekunden ab (jeden Frame)
//   mt.scan_status()      -> Stand        { active=, finished=, progress=0..1, dti=, instances=, ms=, scanned_mb=, skipped_mb= }
//   mt.classes([filter])  -> { {name=, dti=, count=, size=}, ... }  bekannte Klassen (Filter: Teil des Namens)
//   mt.instances(name)    -> { addr, ... }                          Objekte dieser Klasse (Stand des letzten scan)
//   mt.class_of(addr)     -> name | nil                             Klasse des Objekts an addr
//   mt.dti_raw(name)      -> { addr=, words={...}, parent= }         rohe Daten des DTI-Objekts
//   mt.refs(value)        -> { addr, ... }                          Stellen in re0hd.exe (.data), die value enthalten
//   mt.info()             -> Statistik zum Aufbau der DTI (fuer die Auswertung)
//
// Die Annahmen zum Aufbau der DTI sind UNBESTAETIGT, die Statistik in
// mt.info() dient genau dazu, sie zu pruefen.
#pragma once

struct lua_State;

namespace remods::mt {

void register_lua(lua_State* L);

}  // namespace remods::mt
