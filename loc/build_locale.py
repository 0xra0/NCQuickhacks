#!/usr/bin/env python3
"""Build the ArchiveXL onscreen-localization resources for NCQuickhacks.

The English strings are READ OUT OF THE TWEAK YAML on first run rather than
retyped, then persisted to strings-en.json. The Ukrainian strings live in UA
below.

  python3 build_locale.py <depot-local-dir> [--rewrite-yaml]

--rewrite-yaml replaces the literal strings in the YAML with the bare secondary
keys. It is idempotent: a field already holding a key is left alone.
"""
import io, json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
TWEAKS = os.path.join(HERE, "..", "r6", "tweaks", "NCQuickhacks")
YAMLS = ["NCQuickhacks.yaml", "NCQuickhacks2.yaml"]

# TweakDB record -> localization key. One key per distinct on-screen string.
# The weapon-mod records (NCQ_WM_*) are authored with keys from the start, so
# they need no entry here - they are validated via UA/strings-en.json only.
KEYS = {
    "Items.NCQ_SmartLinkScrambleProgram":              "NCQ_SmartLinkScramble_name",
    "BaseStatusEffect.NCQ_SmartLinkScramble_ui":       "NCQ_SmartLinkScramble_name",
    "EquipmentGLP.NCQ_SmartLinkScrambleProgram_ui":    "NCQ_SmartLinkScramble_desc",

    "Items.NCQ_ReflexJammerProgram":                   "NCQ_ReflexJammer_name",
    "EquipmentGLP.NCQ_ReflexJammerProgram_ui":         "NCQ_ReflexJammer_desc",
    "BaseStatusEffect.NCQ_ReflexJammer_ui":            "NCQ_ReflexJammer_se",
    "BaseStatusEffect.NCQ_ReflexMisfire_ui":           "NCQ_ReflexMisfire_se",

    "Items.NCQ_OpticOverwriteProgram":                 "NCQ_OpticOverwrite_name",
    "BaseStatusEffect.NCQ_OpticOverwrite_ui":          "NCQ_OpticOverwrite_name",
    "EquipmentGLP.NCQ_OpticOverwriteProgram_ui":       "NCQ_OpticOverwrite_desc",

    "Items.NCQ_PhantomOverlayProgram":                 "NCQ_PhantomOverlay_name",
    "BaseStatusEffect.NCQ_PhantomOverlay_ui":          "NCQ_PhantomOverlay_name",
    "EquipmentGLP.NCQ_PhantomOverlayProgram_ui":       "NCQ_PhantomOverlay_desc",

    "Items.NCQ_MotorCortexInversionProgram":           "NCQ_MotorCortex_name",
    "BaseStatusEffect.NCQ_MotorCortexInversion_ui":    "NCQ_MotorCortex_name",
    "EquipmentGLP.NCQ_MotorCortexInversionProgram_ui": "NCQ_MotorCortex_desc",

    "Items.NCQ_AdrenalineOverdoseProgram":             "NCQ_AdrenalineOverdose_name",
    "BaseStatusEffect.NCQ_AdrenalineOverdose_ui":      "NCQ_AdrenalineOverdose_name",
    "EquipmentGLP.NCQ_AdrenalineOverdoseProgram_ui":   "NCQ_AdrenalineOverdose_desc",
    "BaseStatusEffect.NCQ_AdrenalineCrash_ui":         "NCQ_AdrenalineCrash_se",

    "Items.NCQ_CryptoSiphonProgram":                   "NCQ_CryptoSiphon_name",
    "BaseStatusEffect.NCQ_CryptoSiphon_ui":            "NCQ_CryptoSiphon_name",
    "EquipmentGLP.NCQ_CryptoSiphonProgram_ui":         "NCQ_CryptoSiphon_desc",
}

# Rich-text markup is identical in both locales - only the prose differs.
H = '<Rich color="TooltipText.cyberwareDescriptionHighlightColor" style="Semi-Bold">'
E = "</>"


def _wm(hack_ua):
    """Weapon-mod tooltip line - same shape for every hack."""
    return f"- Влучання мають {H}шанс завантажити{E} квікхак {H}«{hack_ua}»{E}:\n"


UA = {
    "NCQ_SmartLinkScramble_name": "Збій смартлінка",
    "NCQ_SmartLinkScramble_desc":
        f"Заливає в цільовий смарт-процесор наведення потік сміттєвої телеметрії. "
        f"Протягом {H}10 секунд{E} кожен самонавідний набій, який вони випустять, "
        f"{H}втрачає захоплення на вас{E} і перенаводиться на найближче тіло в полі "
        f"зору — зазвичай на когось із їхнього ж загону.\n\n"
        f"Союзники не розуміють, що сталося, і {H}вогонь у відповідь не відкриють{E}. "
        f"Не відстежується.",

    "NCQ_ReflexJammer_name": "Глушник рефлекс-бустера",
    "NCQ_ReflexJammer_se":   "Глушіння рефлексів",
    "NCQ_ReflexMisfire_se":  "Нейрозбій",
    "NCQ_ReflexJammer_desc":
        f"Ставить {H}12-секундну{E} пастку розсинхрону на шину рефлекс-бустера цілі. "
        f"Вона не робить нічого, доки ціль не спробує ним скористатися.\n\n"
        f"Щойно вони активують {H}сандевістан, керензіков чи бойовий ухил{E}, "
        f"замість цього спрацьовує нейрозбій: {H}сповільнення часу придушується{E}, "
        f"їх заклинює, броня обвалюється, і вони отримують сплеск електрошкоди.\n\n"
        f"Що більше в них хрому — то сильніше б'є.",

    "NCQ_OpticOverwrite_name": "Перезапис оптики",
    "NCQ_OpticOverwrite_desc":
        f"Переписує {H}мітки «свій-чужий»{E}, які ціль транслює власному загону. "
        f"Протягом {H}15 секунд{E} кожен союзник у радіусі 30 м читає їх як "
        f"оперативника Militech і {H}відкриває вогонь{E}.\n\n"
        f"Ціль відстрілюється. Ви в цьому обміні не берете участі — "
        f"{H}уваги до вас не привертається{E}.\n\n"
        f"Після завершення злому всі мітки відновлюються.",

    "NCQ_PhantomOverlay_name": "Фантомний оверлей",
    "NCQ_PhantomOverlay_desc":
        f"Завантажує сфабрикований оптичний контакт просто у зорову кору цілі. "
        f"Протягом {H}12 секунд{E} вони й кожен союзник у радіусі 35 м бачать тіло, "
        f"якого немає, і {H}ламають стрій, щоб зійтися на ньому{E}.\n\n"
        f"Фантом завжди проєктується подалі від вашої позиції. Не відстежується.",

    "NCQ_MotorCortex_name": "Інверсія моторної кори",
    "NCQ_MotorCortex_desc":
        f"Локальний дизраптор по моторній корі. Протягом {H}10 секунд{E} ціль "
        f"{H}десинхронізується з реальним часом{E} — рухи стають млявими й "
        f"смиканими, прицілювання розсипається, робота зі зброєю летить шкереберть.\n\n"
        f"Перетворює броньованого стрільця на тягар, не вбиваючи його.",

    "NCQ_AdrenalineOverdose_name": "Передоз адреналіну",
    "NCQ_AdrenalineCrash_se":      "Адреналіновий відкат",
    "NCQ_AdrenalineOverdose_desc":
        f"Перехоплює ін'єктори бойових стимуляторів цілі й зливає весь резервуар. "
        f"Протягом {H}15 секунд{E} вони {H}некеровано шаленіють{E} — ігнорують "
        f"укриття й атакують усе, що ближче, включно з власним загоном.\n\n"
        f"Довго таке навантаження не витримати: вони {H}втрачають здоров'я щосекунди{E}, "
        f"а коли порив спадає — лишаються знесиленими й повністю відкритими.",

    "NCQ_CryptoSiphon_name": "Криптосифон",
    "NCQ_CryptoSiphon_desc":
        f"Підсаджує стелс-черв'яка на особистий шард цілі. Протягом {H}30 секунд{E} "
        f"він тихо зливає {H}едді щосекунди{E} на ваш рахунок.\n\n"
        f"Вбийте їх, доки черв'як ще всередині, і він виконає "
        f"{H}протокол банкрутства{E}, скинувши вам залишок їхнього балансу — "
        f"тим більший, чим довше ви дали їм пожити.\n\n"
        f"Нелетально й не відстежується.",

    # Weapon-mod variants - "Quickhack Weapon Mods" (Nexus 24568) integration.
    "NCQ_WM_SmartLinkScramble_name":    "Скремблер смартлінка",
    "NCQ_WM_SmartLinkScramble_desc":    _wm("Збій смартлінка"),
    "NCQ_WM_ReflexJammer_name":         "Модуль глушіння рефлексів",
    "NCQ_WM_ReflexJammer_desc":         _wm("Глушник рефлекс-бустера"),
    "NCQ_WM_OpticOverwrite_name":       "Модуль перезапису оптики",
    "NCQ_WM_OpticOverwrite_desc":       _wm("Перезапис оптики"),
    "NCQ_WM_PhantomOverlay_name":       "Модуль фантомного оверлея",
    "NCQ_WM_PhantomOverlay_desc":       _wm("Фантомний оверлей"),
    "NCQ_WM_MotorCortexInversion_name": "Інвертор моторної кори",
    "NCQ_WM_MotorCortexInversion_desc": _wm("Інверсія моторної кори"),
    "NCQ_WM_AdrenalineOverdose_name":   "Спайк адреналінових ін'єкторів",
    "NCQ_WM_AdrenalineOverdose_desc":   _wm("Передоз адреналіну"),
    "NCQ_WM_CryptoSiphon_name":         "Черв'як криптосифона",
    "NCQ_WM_CryptoSiphon_desc":         _wm("Криптосифон"),
}

# Scanner-wheel strings.  Interactions.*.caption / .description are CName fields
# read through LocKeyToString(), so they must hold a secondary key - literal
# prose there renders as "LocKey#<hash of the prose>".  The status-effect UI
# records are String fields instead and need the LocKey# prefix; the YAML
# carries the right form for each.
UA.update({
    "NCQ_SmartLinkScramble_short":  "Псує наведення смартзброї. Самонавідні набої б'ють по своїх.",
    "NCQ_ReflexJammer_short":       "Ставить пастку розсинхрону. Спрацює, щойно ціль увімкне рефлекс-хром.",
    "NCQ_OpticOverwrite_short":     "Підміняє мітки «свій-чужий». Власний загін читає ціль як Militech і б'є.",
    "NCQ_PhantomOverlay_short":     "Вписує фальшивий контакт у їхню оптику. Загін ламає стрій і йде на нього.",
    "NCQ_MotorCortex_short":        "Плутає просторову орієнтацію. Ціль випадає з реального часу й не влучає.",
    "NCQ_AdrenalineOverdose_short": "Відкриває інжектори навстіж. Некерований берсерк, за який платить серце.",
    "NCQ_CryptoSiphon_short":       "Заражає їхній шард. Тягне едді, поки ціль жива, і зливає рахунок по смерті.",

    "NCQ_SmartLinkScramble_sedesc":  "Співпроцесор наведення пошкоджено. Самонавідний вогонь не захоплює вас.",
    "NCQ_ReflexJammer_sedesc":       "Шину рефлексів розсинхронізовано. Будь-яка спроба сповільнити час дасть збій.",
    "NCQ_ReflexMisfire_sedesc":      "Нейрозбій. Броня вимкнена.",
    "NCQ_OpticOverwrite_sedesc":     "Мітки «свій-чужий» підмінено. Власний загін читає ціль як ворога.",
    "NCQ_PhantomOverlay_sedesc":     "Оптичний канал скомпрометовано. Ціль веде контакт, якого не існує.",
    "NCQ_MotorCortex_sedesc":        "Моторну кору розсинхронізовано. Рух і прицілювання ненадійні.",
    "NCQ_AdrenalineOverdose_sedesc": "Синтетичний адреналін затоплює організм. Критичне навантаження на серце.",
    "NCQ_CryptoSiphon_sedesc":       "Прихований черв'як у персональному шарді. Кошти витікають.",
    "NCQ_AdrenalineCrash_sedesc":    "Серцево-судинний зрив. Задихається, беззахисний.",
})


FIELD = re.compile(r"^(\s+)(displayName|localizedDescription): (.*)$")
REC = re.compile(r"^([A-Za-z][A-Za-z0-9_.]*):\s*$")


def scan(rewrite=False):
    """Pull the English strings out of the YAML; optionally swap in the keys."""
    en = {}
    for fn in YAMLS:
        path = os.path.join(TWEAKS, fn)
        out, rec, changed = [], None, 0
        for line in io.open(path, encoding="utf-8"):
            m = REC.match(line)
            if m:
                rec = m.group(1)
            f = FIELD.match(line.rstrip("\n"))
            if f and rec in KEYS:
                indent, field, raw = f.groups()
                key = KEYS[rec]
                want_desc = field == "localizedDescription"
                if want_desc != key.endswith("_desc"):
                    out.append(line); continue
                val = raw.strip()
                if val in ("''", '""') or val == key or val.startswith("LocKey#"):
                    out.append(line); continue
                if val.startswith('"') and val.endswith('"'):
                    val = json.loads(val)
                elif val.startswith("'") and val.endswith("'"):
                    val = val[1:-1].replace("''", "'")
                en[key] = val
                out.append(f"{indent}{field}: {key}\n")
                changed += 1
                continue
            out.append(line)
        if rewrite and changed:
            io.open(path, "w", encoding="utf-8").writelines(out)
            print(f"  {fn}: rewrote {changed} field(s) to keys")
    return en


def resource(entries, depot_name):
    return {
        "Header": {"WKitJsonVersion": "0.0.8", "GameVersion": 2000,
                   "DataType": "CR2W", "ArchiveFileName": depot_name},
        "Data": {"Version": 195, "BuildVersion": 0, "RootChunk": {
            "$type": "JsonResource",
            "cookingPlatform": "PLATFORM_PC",
            "root": {"HandleId": "0", "Data": {
                "$type": "localizationPersistenceOnScreenEntries",
                "entries": [
                    {"$type": "localizationPersistenceOnScreenEntry",
                     "femaleVariant": text, "maleVariant": "",
                     "primaryKey": "0", "secondaryKey": key}
                    for key, text in sorted(entries.items())
                ]}}
        }, "EmbeddedFiles": []},
    }


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    outdir = sys.argv[1]
    rewrite = "--rewrite-yaml" in sys.argv

    # Once the YAML holds keys the English no longer lives there, so the first
    # extraction persists it here and every later build reads it back.
    store = os.path.join(HERE, "strings-en.json")
    en = scan(rewrite=rewrite)
    if en:
        merged = {}
        if os.path.exists(store):
            merged.update(json.load(io.open(store, encoding="utf-8")))
        merged.update(en)
        json.dump(merged, io.open(store, "w", encoding="utf-8"),
                  indent=2, ensure_ascii=False, sort_keys=True)
        en = merged
    elif os.path.exists(store):
        en = json.load(io.open(store, encoding="utf-8"))
    else:
        sys.exit("no English strings: YAML holds keys and strings-en.json is missing")

    # Every key must exist in BOTH locales or that string renders blank.
    both = set(en) | set(UA)
    missing_ua = sorted(both - set(UA))
    missing_en = sorted(both - set(en))
    if missing_ua:
        sys.exit(f"ua-ua missing keys: {missing_ua}")
    if missing_en:
        sys.exit(f"en-us missing keys: {missing_en}")

    os.makedirs(outdir, exist_ok=True)
    for loc, entries in (("en-us", en), ("ua-ua", UA)):
        depot = f"base\\\\ncquickhacks\\\\local\\\\{loc}.json"
        p = os.path.join(outdir, f"{loc}.json.json")
        json.dump(resource(entries, depot), io.open(p, "w", encoding="utf-8"),
                  indent=2, ensure_ascii=False)
        print(f"  wrote {loc}.json.json  ({len(entries)} entries)")


if __name__ == "__main__":
    main()
